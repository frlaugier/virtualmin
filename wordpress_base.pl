sub script_wordpress_desc
{
	return "WordPress";
}

sub script_wordpress_uses
{
	return ( "php" );
}

sub script_wordpress_versions
{
	return ( "0.0.1" );
}

sub script_wordpress_category
{
	return "Blog";
}

sub script_wordpress_php_vers
{
	return ( 4, 5 );
}

sub script_wordpress_php_modules
{
	return ("mysql");
}

sub script_horde_pear_modules
{
	return ("Log", "Mail", "Mail_Mime", "DB");
}

sub script_twiki_perl_modules
{
	return ( "CGI::Session", "Net::SMTP" );
}

sub script_django_python_modules
{
	return ( "setuptools", "MySQLdb" );
}

sub script_wordpress_depends
{
	local ($d, $ver) = @_;
	&has_domain_databases($d, [ "mysql" ]) ||
	return "WordPress requires a MySQL database" if (!@dbs);
	&require_mysql();
	if (&mysql::get_mysql_version() < 4) {
		return "WordPress requires MySQL version 4 or higher";
	}
	return undef;
}

sub script_wordpress_dbs
{
	local ($d, $ver) = @_;
	return ("mysql");
}

sub script_wordpress_params
{
	local ($d, $ver, $upgrade) = @_;
	local $rv;
	local $hdir = &public_html_dir($d, 1);
	if ($upgrade) {
		# Options are fixed when upgrading
		local ($dbtype, $dbname) = split(/_/, $upgrade->{'opts'}->{'db'}, 2);
		$rv .= &ui_table_row("Database for WordPress tables", $dbname);
		local $dir = $upgrade->{'opts'}->{'dir'};
		$dir =~ s/^$d->{'home'}\///;
		$rv .= &ui_table_row("Install directory", $dir);
	}
	else {
		# Show editable install options
		local @dbs = &domain_databases($d, [ "mysql" ]);
		$rv .= &ui_table_row("Database for WordPress tables",
		&ui_database_select("db", undef, \@dbs, $d, "wordpress"));
		$rv .= &ui_table_row("Install sub-directory under <tt>$hdir</tt>",
		&ui_opt_textbox("dir", "wordpress", 30,
		"At top level"));
	}
	return $rv;
}

sub script_wordpress_parse
{
	local ($d, $ver, $in, $upgrade) = @_;
	if ($upgrade) {
		# Options are always the same
		return $upgrade->{'opts'};
	}
	else {
		local $hdir = &public_html_dir($d, 0);
		$in{'dir_def'} || $in{'dir'} =~ /\S/ && $in{'dir'} !~ /\.\./ ||
		return "Missing or invalid installation directory";
		local $dir = $in{'dir_def'} ? $hdir : "$hdir/$in{'dir'}";
		local ($newdb) = ($in->{'db'} =~ s/^\*//);
		return { 'db' => $in->{'db'},
		'newdb' => $newdb,
		'multi' => $in->{'multi'},
		'dir' => $dir,
		'path' => $in{'dir_def'} ? "/" : "/$in{'dir'}", };
	}
}

sub script_wordpress_check
{
	local ($d, $ver, $opts, $upgrade) = @_;
	$opts->{'dir'} =~ /^\// || return "Missing or invalid install directory";
	$opts->{'db'} || return "Missing database";
	if (-r "$opts->{'dir'}/wp-login.php") {
		return "WordPress appears to be already installed in the selected directory";
	}
	local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	local $clash = &find_database_table($dbtype, $dbname, "wp_.*");
	$clash && return "WordPress appears to be already using the selected database (table $clash)";
	return undef;
}

sub script_wordpress_files
{
	local ($d, $ver, $opts, $upgrade) = @_;
	local @files = ( { 'name' => "source",
	'file' => "latest.tar.gz",
	'url' => "http://wordpress.org/latest.zip",
	'nocache' => 1 } );
	return @files;
}

sub script_wordpress_commands
{
	return ("unzip");
}

sub script_wordpress_install
{
	local ($d, $version, $opts, $files, $upgrade) = @_;
	local ($out, $ex);
	if ($opts->{'newdb'} && !$upgrade) {
		local $err = &create_script_database($d, $opts->{'db'});
		return (0, "Database creation failed : $err") if ($err);
	}
	local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	local $dbuser = $dbtype eq "mysql" ? &mysql_user($d) : &postgres_user($d);
	local $dbpass = $dbtype eq "mysql" ? &mysql_pass($d) : &postgres_pass($d, 1);
	local $dbphptype = $dbtype eq "mysql" ? "mysql" : "psql";
	local $dbhost = &get_database_host($dbtype);
	local $dberr = &check_script_db_connection($dbtype, $dbname, $dbuser, $dbpass);
	return (0, "Database connection failed : $dberr") if ($dberr);
}

# Create target dir
if (!-d $opts->{'dir'}) {
	$out = &run_as_domain_user($d, "mkdir -p ".quotemeta($opts->{'dir'}));
	-d $opts->{'dir'} ||
	return (0, "Failed to create directory : <tt>$out</tt>.");
}

# Extract tar file to temp dir
local $temp = &transname();
mkdir($temp, 0755);
chown($d->{'uid'}, $d->{'gid'}, $temp);
$out = &run_as_domain_user($d, "cd ".quotemeta($temp).
" && unzip $files->{'source'}");
local $verdir = "wordpress";
-r "$temp/$verdir/wp-login.php" ||
return (0, "Failed to extract source : <tt>$out</tt>.");

# Move html dir to target
$out = &run_as_domain_user($d, "cp -rp ".quotemeta($temp)."/$verdir/* ".
quotemeta($opts->{'dir'}));
local $cfileorig = "$opts->{'dir'}/wp-config-sample.php";
local $cfile = "$opts->{'dir'}/wp-config.php";
-r $cfileorig || return (0, "Failed to copy source : <tt>$out</tt>.");

# Copy and update the config file
if (!-r $cfile) {
	&run_as_domain_user($d, "cp ".quotemeta($cfileorig)." ".
	quotemeta($cfile));
	local $lref = &read_file_lines($cfile);
	local $l;
	foreach $l (@$lref) {
		if ($l =~ /^define\('DB_NAME',/) {
			$l = "define('DB_NAME', '$dbname');";
		}
		if ($l =~ /^define\('DB_USER',/) {
			$l = "define('DB_USER', '$dbuser');";
		}
		if ($l =~ /^define\('DB_HOST',/) {
			$l = "define('DB_HOST', '$dbhost');";
		}
		if ($l =~ /^define\('DB_PASSWORD',/) {
			$l = "define('DB_PASSWORD', '$dbpass');";
		}
		if ($opts->{'multi'}) {
			if ($l =~ /^define\('VHOST',/) {
				$l = "define('VHOST', '');";
			}
			if ($l =~ /^\$base\s*=/) {
				$l = "\$base = '$opts->{'path'}/';";
			}
		}
	}
	&flush_file_lines($cfile);
}

if (!$upgrade) {
	# Run the SQL setup script
	if ($dbtype eq "mysql") {
		local $sqlfile = "$opts->{'dir'}/tables-mysql.sql";
		&require_mysql();
		($ex, $out) = &mysql::execute_sql_file($dbname, $sqlfile, $dbuser, $dbpass);
		$ex && return (0, "Failed to run database setup script : <tt>$out</tt>.");
	}

	local $url = &script_path_url($d, $opts).
	($upgrade ? "wp-admin/upgrade.php" : "wp-admin/install.php");
	local $userurl = &script_path_url($d, $opts);
	local $rp = $opts->{'dir'};
	$rp =~ s/^$d->{'home'}\///;
	return (1, "WordPress installation complete. It can be accessed at <a href='$url'>$url</a>.", "Under $rp using $dbphptype database $dbname", $userurl);
}

sub script_wordpress_uninstall
{
	local ($d, $version, $opts) = @_;

	# Remove the contents of the target directory
	local $derr = &delete_script_install_directory($d, $opts);
	return (0, $derr) if ($derr);

	# Remove all wp_ tables from the database
	local ($dbtype, $dbname) = split(/_/, $opts->{'db'}, 2);
	if ($dbtype eq "mysql") {
		# Delete from MySQL
		&require_mysql();
		foreach $t (&mysql::list_tables($dbname)) {
			if ($t =~ /^wp_/) {
				&mysql::execute_sql_logged($dbname,
				"drop table ".&mysql::quotestr($t));
			}
		}
	}
	else {
		# Delete from PostgreSQL
		&require_postgres();
		foreach $t (&postgresql::list_tables($dbname)) {
			if ($t =~ /^wp_/) {
				&postgresql::execute_sql_logged($dbname,
				"drop table $t");
			}
		}
	}

	# Take out the DB
	if ($opts->{'newdb'}) {
		&delete_script_database($d, $opts->{'db'});
	}

	return (1, "WordPress directory and tables deleted.");
}

sub script_wordpress_passmode
{
	return 1;
}
