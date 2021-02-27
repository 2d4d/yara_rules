
/*

Webshell rules by Arnim Rupp

Rationale behind the rules:
1. a webshell must always execute some kind of payload (in $payload*). the payload is either:
-- direct php function like exec, file write, sql, ...
-- indirect via eval, self defined functions, callbacks, reflection, ...
2. a webshell must always have some way to get the attackers input, e.g. for PHP in $_GET, php://input or $_SERVER (HTTP for headers). 

The input may be hidden in obfuscated code, so we look for either:
a) payload + input
b) eval-style-payloads + obfuscation
c) includers (webshell is split in 2+ files)
d) unique strings, if the coder doesn't even intend to hide 

Additional conditions will be added to reduce false positves. Check all findings for unintentional webshells aka vulnerabilities ;)

The rules named "suspicous_" are commented by default. uncomment them to find more potentially malicious files at the price of more false positives. if that finds too many results to manually check, you can compare the hashes to virustotal with e.g. https://github.com/Neo23x0/munin

Some samples in the collection where UTF-16 and at least PHP and Java support it, so I use "wide ascii" for all strings. The performance impact is 1%. See also https://thibaud-robin.fr/articles/bypass-filter-upload/

Rules tested on the following webshell repos and collections:
	https://github.com/sensepost/reGeorg
	https://github.com/WhiteWinterWolf/wwwolf-php-webshell
	https://github.com/k8gege/Ladon
	https://github.com/x-o-r-r-o/PHP-Webshells-Collection
	https://github.com/mIcHyAmRaNe/wso-webshell
	https://github.com/LandGrey/webshell-detect-bypass
	https://github.com/threedr3am/JSP-Webshells
	https://github.com/02bx/webshell-venom
	https://github.com/pureqh/webshell
	https://github.com/secwiki/webshell-2
	https://github.com/zhaojh329/rtty
	https://github.com/modux/ShortShells
	https://github.com/epinna/weevely3
	https://github.com/chrisallenlane/novahot
	https://github.com/malwares/WebShell
	https://github.com/tanjiti/webshellSample
	https://github.com/L-codes/Neo-reGeorg
	https://github.com/bayufedra/Tiny-PHP-Webshell
	https://github.com/b374k/b374k
	https://github.com/wireghoul/htshells
	https://github.com/securityriskadvisors/cmd.jsp
	https://github.com/WangYihang/Webshell-Sniper
	https://github.com/Macr0phag3/WebShells
	https://github.com/s0md3v/nano
	https://github.com/JohnTroony/php-webshells
	https://github.com/linuxsec/indoxploit-shell
	https://github.com/hayasec/reGeorg-Weblogic
	https://github.com/nil0x42/phpsploit
	https://github.com/mperlet/pomsky
	https://github.com/FunnyWolf/pystinger
	https://github.com/tanjiti/webshellsample
	https://github.com/lcatro/php-webshell-bypass-waf
	https://github.com/zhzyker/exphub
	https://github.com/dotcppfile/daws
	https://github.com/lcatro/PHP-WebShell-Bypass-WAF
	https://github.com/ysrc/webshell-sample
	https://github.com/JoyChou93/webshell
	https://github.com/k4mpr3t/b4tm4n
	https://github.com/mas1337/webshell
	https://github.com/tengzhangchao/pycmd
	https://github.com/bartblaze/PHP-backdoors
	https://github.com/antonioCoco/SharPyShell
	https://github.com/xl7dev/WebShell
	https://github.com/BlackArch/webshells
	https://github.com/sqlmapproject/sqlmap
	https://github.com/Smaash/quasibot
	https://github.com/tennc/webshell

Webshells in these repos after fdupes run: 4722
Old signature-base rules found: 1315
This rules found: 3286
False positives in 8gb of common webapps plus yara-ci: 2

*/

//                               _
//     __ _  ___ _ __   ___ _ __(_) ___
//    / _` |/ _ \ '_ \ / _ \ '__| |/ __|
//   | (_| |  __/ | | |  __/ |  | | (__
//    \__, |\___|_| |_|\___|_|  |_|\___|
//    |___/


import "math"

private rule webshell_encoded_stats {
	meta:
		description = "Webshell having statistical signs of encoded code which gets dynamically executed"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/07"
	condition:
		// file shouldn't be too small to have big enough data for math.entropy
		filesize > 2KB and 
		// ignore first and last 500bytes because they usually contain code for decoding and executing
		math.entropy(500, filesize-500) >= 5.7 and
		// encoded text has a higher mean than text or code because it's missing the spaces and special chars with the low numbers
		math.mean(500, filesize-500) > 80 and
		// deviation of base64 is ~20 according to CyberChef_v9.21.0.html#recipe=Generate_Lorem_Ipsum(3,'Paragraphs')To_Base64('A-Za-z0-9%2B/%3D')To_Charcode('Space',10)Standard_Deviation('Space')
		// lets take a bit more because it might not be pure base64 also include some xor, shift, replacement, ...
		// 89 is the mean of the base64 chars
		math.deviation(500, filesize-500, 89.0) < 23
}


//           _
//     _ __ | |__  _ __ 
//    | '_ \| '_ \| '_ \
//    | |_) | | | | |_) |
//    | .__/|_| |_| .__/
//    |_|         |_|
//    ... is crazy in what it allows to define own functions

private rule php_false_positive {
	meta:
		description = "PHP false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		// try to use only strings which would be flagged by themselves as suspicous by other rules, e.g. eval 
		$gfp1  = "eval(\"return [$serialised_parameter" // elgg
		$gfp2  = "$this->assert(strpos($styles, $"
		$gfp3  = "$module = new $_GET['module']($_GET['scope']);"
		$gfp4  = "$plugin->$_POST['action']($_POST['id']);"
		$gfp5  = "$_POST[partition_by]($_POST["
		$gfp6  = "$object = new $_REQUEST['type']($_REQUEST['id']);"
		$gfp7  = "The above example code can be easily exploited by passing in a string such as" // ... ;)
		$gfp8  = "Smarty_Internal_Debug::start_render($_template);"
		$gfp9  = "?p4yl04d=UNION%20SELECT%20'<?%20system($_GET['command']);%20?>',2,3%20INTO%20OUTFILE%20'/var/www/w3bsh3ll.php"
	condition:
		any of ( $gfp* )
}

private rule php_false_positive_tiny {
	meta:
		description = "PHP false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/25"
	strings:
		// try to use only strings which would be flagged by themselves as suspicous by other rules, e.g. eval 
		$gfp_tiny1 = "addslashes" fullword
		$gfp_tiny2 = "escapeshellarg" fullword
		$gfp_tiny3 = "include \"./common.php\";" // xcache
		$gfp_tiny4 = "assert('FALSE')"
	condition:
		any of ( $gfp_tiny* )
}

private rule capa_php {
	meta:
		description = "PHP short tag or <script language=\"php\". Ok if rule limits the filesize to less than 10kb. Use only if needed to reduce false positives because it won't find includer shells anymore. (e.g. <? include 'webshell.txt'?> and the payload in webshell.txt without <? )"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		// this will hit on a lot of non-php files, asp, scripting templates, ... but it works on older php versions
		$php_tag1 = "<?" wide ascii
		$php_tag2 = "<script language=\"php" nocase wide ascii
	condition:
		any of ( $php_tag* )
}

private rule capa_php_old_safe {
	meta:
		description = "PHP short tag <? in the first 100 bytes or the long ones anywhere"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/08"
	strings:
		$php_short = "<?" wide ascii
		// prevent xml and asp from hitting with the short tag
		$no_xml1 = "<?xml version" nocase wide ascii
		$no_xml2 = "<?xml-stylesheet" nocase wide ascii
		$no_asp1 = "<%@LANGUAGE" nocase wide ascii
		$no_asp2 = /<script language="(vb|jscript|c#)/ nocase wide ascii
		$no_pdf = "<?xpacket" 

		// of course the new tags should also match
        // already matched by "<?"
		//$php_new1 = "<?=" wide ascii
		//$php_new2 = "<?php" nocase wide ascii
		$php_new3 = "<script language=\"php" nocase wide ascii
	condition:
		(
			( 
				$php_short in (0..100) or 
				$php_short in (filesize-1000..filesize)
			)
			and not any of ( $no_* )
		) 
		or any of ( $php_new* )
}

private rule capa_php_new {
	meta:
		description = "PHP tags, only <?= and <?php. Use only if needed to reduce false positives because it won't find includer shells anymore. (e.g. <? include 'webshell.txt'?> and the payload in webshell.txt without <? )"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		$new_php1 = "<?=" wide ascii
		$new_php2 = "<?php" nocase wide ascii
		$new_php3 = "<script language=\"php" nocase wide ascii
	condition:
		any of ( $new_php* )
}

private rule capa_php_input {
	meta:
		description = "PHP user input methods, in plain text"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		$inp1 = "php://input" wide ascii
		$inp2 = "_GET[" wide ascii
		$inp3 = "_POST[" wide ascii
		$inp4 = "_REQUEST[" wide ascii
		// PHP automatically adds all the request headers into the $_SERVER global array, prefixing each header name by the "HTTP_" string, so e.g. @eval($_SERVER['HTTP_CMD']) will run any code in the HTTP header CMD
		$inp5 = "_SERVER['HTTP_" wide ascii
		$inp6 = "_SERVER[\"HTTP_" wide ascii
		$inp7 = /getenv[\t ]{0,20}\([\t ]{0,20}['"]HTTP_/ wide ascii
	condition:
		any of ( $inp* )
}

private rule capa_php_payload {
	meta:
		description = "PHP methods for executing OS commands or eval, in plain text"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		// \([^)] to avoid matching on e.g. eval() in comments
		$cpayload1 = /\beval[\t ]*\([^)]/ nocase wide ascii
		$cpayload2 = /\bexec[\t ]*\([^)]/ nocase wide ascii
		$cpayload3 = /\bshell_exec[\t ]*\([^)]/ nocase wide ascii
		$cpayload4 = /\bpassthru[\t ]*\([^)]/ nocase wide ascii
		$cpayload5 = /\bsystem[\t ]*\([^)]/ nocase wide ascii
		$cpayload6 = /\bpopen[\t ]*\([^)]/ nocase wide ascii
		$cpayload7 = /\bproc_open[\t ]*\([^)]/ nocase wide ascii
		$cpayload8 = /\bpcntl_exec[\t ]*\([^)]/ nocase wide ascii
		$cpayload9 = /\bassert[\t ]*\([^)]/ nocase wide ascii
		$cpayload10 = /\bpreg_replace[\t ]*\([^\)]1,1000}\/e/ nocase wide ascii
		$cpayload11 = /\bcreate_function[\t ]*\([^)]/ nocase wide ascii
		$cpayload12 = /\bReflectionFunction[\t ]*\([^)]/ nocase wide ascii
		// TODO: $_GET['func_name']($_GET['argument']);
		// TODO backticks
	condition:
		any of ( $cpayload* )
}

private rule capa_php_callback {
	meta:
		description = "PHP functions which accept callback functions to execute, in plain text"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		$callback1 = /\bob_start[\t ]*\([^)]/ nocase wide ascii
		$callback2 = /\barray_diff_uassoc[\t ]*\([^)]/ nocase wide ascii
		$callback3 = /\barray_diff_ukey[\t ]*\([^)]/ nocase wide ascii
		$callback4 = /\barray_filter[\t ]*\([^)]/ nocase wide ascii
		$callback5 = /\barray_intersect_uassoc[\t ]*\([^)]/ nocase wide ascii
		$callback6 = /\barray_intersect_ukey[\t ]*\([^)]/ nocase wide ascii
		$callback7 = /\barray_map[\t ]*\([^)]/ nocase wide ascii
		$callback8 = /\barray_reduce[\t ]*\([^)]/ nocase wide ascii
		$callback9 = /\barray_udiff_assoc[\t ]*\([^)]/ nocase wide ascii
		$callback10 = /\barray_udiff_uassoc[\t ]*\([^)]/ nocase wide ascii
		$callback11 = /\barray_udiff[\t ]*\([^)]/ nocase wide ascii
		$callback12 = /\barray_uintersect_assoc[\t ]*\([^)]/ nocase wide ascii
		$callback13 = /\barray_uintersect_uassoc[\t ]*\([^)]/ nocase wide ascii
		$callback14 = /\barray_uintersect[\t ]*\([^)]/ nocase wide ascii
		$callback15 = /\barray_walk_recursive[\t ]*\([^)]/ nocase wide ascii
		$callback16 = /\barray_walk[\t ]*\([^)]/ nocase wide ascii
		$callback17 = /\bassert_options[\t ]*\([^)]/ nocase wide ascii
		$callback18 = /\buasort[\t ]*\([^)]/ nocase wide ascii
		$callback19 = /\buksort[\t ]*\([^)]/ nocase wide ascii
		$callback20 = /\busort[\t ]*\([^)]/ nocase wide ascii
		$callback21 = /\bpreg_replace_callback[\t ]*\([^)]/ nocase wide ascii
		$callback22 = /\bspl_autoload_register[\t ]*\([^)]/ nocase wide ascii
		$callback23 = /\biterator_apply[\t ]*\([^)]/ nocase wide ascii
		$callback24 = /\bcall_user_func[\t ]*\([^)]/ nocase wide ascii
		$callback25 = /\bcall_user_func_array[\t ]*\([^)]/ nocase wide ascii
		$callback26 = /\bregister_shutdown_function[\t ]*\([^)]/ nocase wide ascii
		$callback27 = /\bregister_tick_function[\t ]*\([^)]/ nocase wide ascii
		$callback28 = /\bset_error_handler[\t ]*\([^)]/ nocase wide ascii
		$callback29 = /\bset_exception_handler[\t ]*\([^)]/ nocase wide ascii
		$callback30 = /\bsession_set_save_handler[\t ]*\([^)]/ nocase wide ascii
		$callback31 = /\bsqlite_create_aggregate[\t ]*\([^)]/ nocase wide ascii
		$callback32 = /\bsqlite_create_function[\t ]*\([^)]/ nocase wide ascii

		$cfp1 = /ob_start\(['\"]ob_gzhandler/ nocase wide ascii
	condition:
		any of ( $callback* ) and
		not any of ( $cfp* )
}

private rule capa_php_include {
	meta:
		description = "PHP methods for including code from other files, in plain text"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		$cinclude1 = /\binclude[_once]?[\t ]*[('"]/ nocase wide ascii
		$cinclude2 = /\brequire[_once]?[\t ]*[('"]/ nocase wide ascii
	condition:
		capa_php and any of ( $cinclude* )
}

private rule capa_php_dynamic {
	meta:
		description = "PHP webshell using function name from variable, e.g. $a='ev'.'al'; $a($code)"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/11"
	strings:
		$dynamic1 = /\$[a-zA-Z0-9_]{1,10}\(\$/ wide ascii
		$dynamic2 = /\$[a-zA-Z0-9_]{1,10}\("/ wide ascii
		$dynamic3 = /\$[a-zA-Z0-9_]{1,10}\('/ wide ascii
		$dynamic4 = /\$[a-zA-Z0-9_]{1,10}\(str/ wide ascii
		$dynamic5 = /\$[a-zA-Z0-9_]{1,10}\(\)/ wide ascii
		$dynamic6 = /\$[a-zA-Z0-9_]{1,10}\(@/ wide ascii
	condition:
		any of ( $dynamic* )
}


rule webshell_php_generic_tiny {
	meta:
		description = "php webshell having some kind of input and some kind of payload. restricted to small files or would give lots of false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
		hash = "bee1b76b1455105d4bfe2f45191071cf05e83a309ae9defcf759248ca9bceddd"
	condition:
		filesize < 900 
		and capa_php_old_safe
		and capa_php_input
		and capa_php_payload
		and not php_false_positive_tiny
}

rule webshell_php_generic_callback_tiny {
	meta:
		description = "php webshell having some kind of input and using a callback to execute the payload. restricted to small files or would give lots of false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
		hash = "e98889690101b59260e871c49263314526f2093f"
	condition:
		filesize < 1000 
		and capa_php_input
		and capa_php_callback
		and not php_false_positive
		and not php_false_positive_tiny
}

rule webshell_php_generic_nano_input {
	meta:
		description = "php webshell having some kind of input and whatever mechanism to execute it. restricted to small files or would give lots of false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "b492336ac5907684c1b922e1c25c113ffc303ffbef645b4e95d36bc50e932033"
		date = "2021/01/13"
	strings:
		$fp1 = "echo $_POST['" 
		$fp2 = "$http_raw_post_data = file_get_contents('php://input');"
	condition:
		filesize < 90 and 
		capa_php and
		capa_php_input and
		not any of ( $fp* )
}


rule webshell_php_base64_encoded_payloads {
	meta:
		description = "php webshell containg base64 encoded payload"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "88d0d4696c9cb2d37d16e330e236cb37cfaec4cd"
	strings:
		$decode = "base64" nocase wide ascii
		// exec
		$one1 = "leGVj"
		$one2 = "V4ZW"
		$one3 = "ZXhlY"
		$one4 = "UAeABlAGMA"
		$one5 = "lAHgAZQBjA"
		$one6 = "ZQB4AGUAYw"
		// shell_exec
		$two1 = "zaGVsbF9leGVj"
		$two2 = "NoZWxsX2V4ZW"
		$two3 = "c2hlbGxfZXhlY"
		$two4 = "MAaABlAGwAbABfAGUAeABlAGMA"
		$two5 = "zAGgAZQBsAGwAXwBlAHgAZQBjA"
		$two6 = "cwBoAGUAbABsAF8AZQB4AGUAYw"
		// passthru
		$three1 = "wYXNzdGhyd"
		$three2 = "Bhc3N0aHJ1"
		$three3 = "cGFzc3Rocn"
		$three4 = "AAYQBzAHMAdABoAHIAdQ"
		$three5 = "wAGEAcwBzAHQAaAByAHUA"
		$three6 = "cABhAHMAcwB0AGgAcgB1A"
		// system
		$four1 = "zeXN0ZW"
		$four2 = "N5c3Rlb"
		$four3 = "c3lzdGVt"
		$four4 = "MAeQBzAHQAZQBtA"
		$four5 = "zAHkAcwB0AGUAbQ"
		$four6 = "cwB5AHMAdABlAG0A"
		// popen
		$five1 = "wb3Blb"
		$five2 = "BvcGVu"
		$five3 = "cG9wZW"
		$five4 = "AAbwBwAGUAbg"
		$five5 = "wAG8AcABlAG4A"
		$five6 = "cABvAHAAZQBuA"
		// proc_open
		$six1 = "wcm9jX29wZW"
		$six2 = "Byb2Nfb3Blb"
		$six3 = "cHJvY19vcGVu"
		$six4 = "AAcgBvAGMAXwBvAHAAZQBuA"
		$six5 = "wAHIAbwBjAF8AbwBwAGUAbg"
		$six6 = "cAByAG8AYwBfAG8AcABlAG4A"
		// pcntl_exec
		$seven1 = "wY250bF9leGVj"
		$seven2 = "BjbnRsX2V4ZW"
		$seven3 = "cGNudGxfZXhlY"
		$seven4 = "AAYwBuAHQAbABfAGUAeABlAGMA"
		$seven5 = "wAGMAbgB0AGwAXwBlAHgAZQBjA"
		$seven6 = "cABjAG4AdABsAF8AZQB4AGUAYw"
		// eval
		$eight1 = "ldmFs"
		$eight2 = "V2YW"
		$eight3 = "ZXZhb"
		$eight4 = "UAdgBhAGwA"
		$eight5 = "lAHYAYQBsA"
		$eight6 = "ZQB2AGEAbA"
		// assert
		$nine1 = "hc3Nlcn"
		$nine2 = "Fzc2Vyd"
		$nine3 = "YXNzZXJ0"
		$nine4 = "EAcwBzAGUAcgB0A"
		$nine5 = "hAHMAcwBlAHIAdA"
		$nine6 = "YQBzAHMAZQByAHQA"

        // false positives

        // execu
        $execu1 = "leGVjd"
		$execu2 = "V4ZWN1"
		$execu3 = "ZXhlY3"

        // esystem like e.g. filesystem
        $esystem1 = "lc3lzdGVt"
		$esystem2 = "VzeXN0ZW"
		$esystem3 = "ZXN5c3Rlb"

	condition:
		filesize < 300KB and 
		capa_php_old_safe and 
		$decode and (
			( any of ( $one* ) and 
              not any of ( $execu* )
            )   
            or any of ( $two* ) or any of ( $three* ) or 

            ( any of ( $four* ) and
            not any of ( $esystem* )
            ) 
            or any of ( $five* ) or any of ( $six* ) or any of ( $seven* ) or any of ( $eight* ) or any of ( $nine* )
		) 
}

rule webshell_php_unknown_1 {
	meta:
		description = "obfuscated php webshell"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "12ce6c7167b33cc4e8bdec29fb1cfc44ac9487d1"
		hash = "cf4abbd568ce0c0dfce1f2e4af669ad2"
		date = "2021/01/07"
	strings:
		$sp0 = /^<\?php \$[a-z]{3,30} = '/ wide ascii
		$sp1 = "=explode(chr(" wide ascii
		$sp2 = "; if (!function_exists('" wide ascii
		$sp3 = " = NULL; for(" wide ascii
	condition:
		filesize < 300KB and 
		all of ( $sp* )
}

rule webshell_php_generic_eval {
	meta:
		description = "Generic PHP webshell which uses any eval/exec function in the same line with user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "a61437a427062756e2221bfb6d58cd62439d09d9"
		hash = "90c5cc724ec9cf838e4229e5e08955eec4d7bf95"
		date = "2021/01/07"
	strings:
		$geval = /(exec|shell_exec|passthru|system|popen|proc_open|pcntl_exec|eval|assert)[\t ]*(stripslashes\()?[\t ]*(trim\()?[\t ]*\(\$(_POST|_GET|_REQUEST|_SERVER\[['"]HTTP_)/ wide ascii
	condition:
		filesize < 300KB and 
		$geval and 
        not php_false_positive
}

rule webshell_php_double_eval_tiny {
	meta:
		description = "PHP webshell which probably hides the input inside an eval()ed obfuscated string"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "aabfd179aaf716929c8b820eefa3c1f613f8dcac"
		date = "2021/01/11"
		score = 50
	strings:
		$payload = /(\beval[\t ]*\([^)]|\bassert[\t ]*\([^)])/ nocase wide ascii
		$fp1 = "clone" fullword wide ascii
	condition:
		filesize > 70 and 
		filesize < 300 and 
		capa_php and 
		#payload >= 2 and 
		not any of ( $fp* )
}

private rule capa_php_obfuscation_multi {
	meta:
		description = "PHP obfuscation functions which have to be used multiple times, e.g. for each character"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
		score = 50
	strings:
		$o1 = "chr(" nocase wide ascii
		$o2 = "chr (" nocase wide ascii
		// not excactly a string function but also often used in obfuscation
		$o3 = "goto" fullword nocase wide ascii
		$o4 = "\\x9" wide ascii
		$o5 = "\\x3" wide ascii
		// just picking some random numbers because they should appear often enough in a long obfuscated blob and it's faster than a regex
		$o6 = "\\61" wide ascii
		$o7 = "\\44" wide ascii
		$o8 = "\\112" wide ascii
		$o9 = "\\120" wide ascii
		$fp1 = "$goto" wide ascii
	condition:
		// allow different amounts of potential obfuscation functions depending on filesize
		not $fp1 and (
			(
				filesize < 20KB and 
				(
					( #o1+#o2 ) > 50 or
					#o3 > 10 or
					( #o4+#o5+#o6+#o7+#o8+#o9 ) > 20 
				) 
			) or (
				filesize < 200KB and 
				(
					( #o1+#o2 ) > 200 or
					#o3 > 30 or
					( #o4+#o5+#o6+#o7+#o8+#o9 ) > 30 
				) 

			)
		)


}

private rule capa_php_obfuscation_single {
	meta:
		description = "PHP obfuscation functions which can be used on multiple strings"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		$cobfs1 = "gzinflate" fullword nocase wide ascii
		$cobfs2 = "gzuncompress" fullword nocase wide ascii
		$cobfs3 = "gzdecode" fullword nocase wide ascii
		$cobfs4 = "base64_decode" fullword nocase wide ascii
		$cobfs5 = "pack" fullword nocase wide ascii
	condition:
		any of ( $cobfs* )
}

rule webshell_php_obfuscated {
	meta:
		description = "PHP webshell obfuscated"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "eec9ac58a1e763f5ea0f7fa249f1fe752047fa60"
	condition:
		// filesize checked in capa_php_obfuscation_multi
		capa_php_old_safe and 
		capa_php_obfuscation_multi and 
		capa_php_payload and
        not php_false_positive
}

rule webshell_php_obfuscated_str_replace {
	meta:
		description = "PHP webshell which eval()s obfuscated string"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "691305753e26884d0f930cda0fe5231c6437de94"
		hash = "7efd463aeb5bf0120dc5f963b62463211bd9e678"
		hash = "fb655ddb90892e522ae1aaaf6cd8bde27a7f49ef"
		hash = "d1863aeca1a479462648d975773f795bb33a7af2"
		hash = "4d31d94b88e2bbd255cf501e178944425d40ee97"
		hash = "e1a2af3477d62a58f9e6431f5a4a123fb897ea80"
	strings:
		$payload1 = "str_replace" fullword wide ascii
		$payload2 = "function" fullword wide ascii
		$goto = "goto" fullword wide ascii
		//$hex  = "\\x"
		$chr1  = "\\61" wide ascii
		$chr2  = "\\112" wide ascii
		$chr3  = "\\120" wide ascii
	condition:
		filesize < 300KB and 
		capa_php_old_safe and 
		any of ( $payload* ) and 
		#goto > 1 and 
		( #chr1 > 10 or #chr2 > 10 or #chr3 > 10 )
}

rule webshell_php_obfuscated_fopo {
	meta:
		description = "PHP webshell which eval()s obfuscated string"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "fbcff8ea5ce04fc91c05384e847f2c316e013207"
		hash = "6da57ad8be1c587bb5cc8a1413f07d10fb314b72"
		hash = "a698441f817a9a72908a0d93a34133469f33a7b34972af3e351bdccae0737d99"
		date = "2021/01/12"
	strings:
		$payload = /(\beval[\t ]*\([^)]|\bassert[\t ]*\([^)])/ nocase wide ascii
		// ;@eval(
		$one1 = "7QGV2YWwo" wide ascii
		$one2 = "tAZXZhbC" wide ascii
		$one3 = "O0BldmFsK" wide ascii
		$one4 = "sAQABlAHYAYQBsACgA" wide ascii
		$one5 = "7AEAAZQB2AGEAbAAoA" wide ascii
		$one6 = "OwBAAGUAdgBhAGwAKA" wide ascii
		// ;@assert(
		$two1 = "7QGFzc2VydC" wide ascii
		$two2 = "tAYXNzZXJ0K" wide ascii
		$two3 = "O0Bhc3NlcnQo" wide ascii
		$two4 = "sAQABhAHMAcwBlAHIAdAAoA" wide ascii
		$two5 = "7AEAAYQBzAHMAZQByAHQAKA" wide ascii
		$two6 = "OwBAAGEAcwBzAGUAcgB0ACgA" wide ascii
	condition:
		filesize < 3000KB and
		capa_php_old_safe and 
		$payload and (
			any of ( $one* ) or any of ( $two* )
		)
}

private rule capa_os_strings {
	meta:
		description = "typical webshell OS commands"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
	strings:
		// windows = nocase
		$w1 = "net localgroup administrators" nocase wide ascii
		$w2 = "net user" nocase wide ascii
		$w3 = "/add" nocase wide ascii
		// linux stuff, case sensitive:
		$l1 = "/etc/shadow" wide ascii
		$l2 = "/etc/ssh/sshd_config" wide ascii
		$take_two1 = "net user" nocase wide ascii
		$take_two2 = "/add" nocase wide ascii
	condition:
		filesize < 300KB and 
        not uint16(0) == 0x5a4d and (
            all of ( $w* ) or
            all of ( $l* ) or
            2 of ( $take_two* ) 
        )
}

rule webshell_php_gzinflated {
	meta:
		description = "PHP webshell which directly eval()s obfuscated string"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "49e5bc75a1ec36beeff4fbaeb16b322b08cf192d"
	strings:
		$php = "<?" wide ascii
		$payload1 = "eval(gzinflate(base64_decode(" wide ascii
		$payload2 = "eval(\"?>\".gzinflate(base64_decode(" wide ascii
		$payload3 = "eval(gzuncompress(base64_decode(" wide ascii
		$payload4 = "eval(\"?>\".gzuncompress(base64_decode(" wide ascii
		$payload5 = "eval(gzdecode(base64_decode(" wide ascii
		$payload6 = "eval(\"?>\".gzdecode(base64_decode(" wide ascii
		$payload7 = "eval(base64_decode(" wide ascii
		$payload8 = "eval(pack(" wide ascii
	condition:
		filesize < 700KB and 
		$php and 1 of ( $payload* )
}

rule webshell_php_obfuscated_2 {
	meta:
		description = "PHP webshell which eval()s obfuscated string"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "1d4b374d284c12db881ba42ee63ebce2759e0b14"
		date = "2021/01/13"
	strings:
		// <?php function vUMmFr($MkUOmK) { $MkUOmK=gzinflate(base64_decode($MkUOmK)); for($i=0;$i<strlen($MkUOmK);$i++) { $MkUOmK[$i] = chr(ord($MkUOmK[$i])-1); } return $MkUOmK; }eval
		$obf1 = "function" fullword wide ascii
		$obf2 = "base64_decode" fullword wide ascii
		$obf3 = "chr" fullword wide ascii
		$obf4 = "ord" fullword wide ascii
		$payload1 = "eval" fullword wide ascii
		$payload2 = "assert" fullword wide ascii
	condition:
		filesize < 300KB and 
		capa_php_old_safe and 
		1 of ( $payload* ) and 
		$obf1 in (0..500) and
		$obf2 in (0..500) and
		$obf3 in (0..500) and
		$obf4 in (0..500) 
}

rule webshell_php_includer {
	meta:
		description = "PHP webshell which eval()s another included file"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "3a07e9188028efa32872ba5b6e5363920a6b2489"
		date = "2021/01/13"
	strings:
		$payload1 = "eval" fullword wide ascii
		$payload2 = "assert" fullword wide ascii
		$include1 = "$_FILE" wide ascii
		$include2 = "include" wide ascii
	condition:
		filesize < 200 and 
		capa_php and 
		1 of ( $payload* ) and 
		1 of ( $include* )
}


rule webshell_php_dynamic {
	meta:
		description = "PHP webshell using function name from variable, e.g. $a='ev'.'al'; $a($code)"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "65dca1e652d09514e9c9b2e0004629d03ab3c3ef"
		hash = "b8ab38dc75cec26ce3d3a91cb2951d7cdd004838"
		hash = "c4765e81550b476976604d01c20e3dbd415366df"
		date = "2021/01/13"
		score = 60
	strings:
		$fp = "whoops_add_stack_frame" wide ascii
	condition:
		filesize < 200 and 
		capa_php and 
		capa_php_dynamic and
		not $fp
}

rule webshell_php_dynamic_big {
	meta:
		description = "PHP webshell using $a($code) for kind of eval with encoded blob to decode, e.g. b374k"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/07"
		score = 50
	condition:
		filesize < 3000KB and 
		capa_php_new and 
		capa_php_dynamic and
		webshell_encoded_stats
}

rule webshell_php_encoded_big {
	meta:
		description = "PHP webshell using some kind of eval with encoded blob to decode"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/07"
		score = 50
	condition:
		filesize < 3000KB and 
		capa_php_new and 
		capa_php_payload and 
		webshell_encoded_stats
}


rule webshell_php_generic_backticks {
	meta:
		description = "Generic PHP webshell which uses backticks directly on user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "339f32c883f6175233f0d1a30510caa52fdcaa37"
	strings:
		$backtick = /`[\t ]*\$(_POST\[|_GET\[|_REQUEST\[|_SERVER\['HTTP_)/ wide ascii
	condition:
		// arg, can't search everywhere because lots of people write comments like "the value of `$_POST['action']`. Default false." :(
		filesize < 200 and 
		capa_php and
		$backtick
}

rule webshell_php_generic_backticks_obfuscated {
	meta:
		description = "Generic PHP webshell which uses backticks directly on user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "23dc299f941d98c72bd48659cdb4673f5ba93697"
		date = "2021/01/07"
	strings:
		$s1 = /echo[\t ]*\(?`\$/ wide ascii
	condition:
		filesize < 500 and 
		capa_php_old_safe and
		$s1
}

rule webshell_php_by_string {
	meta:
		description = "PHP Webshells which contain unique strings, lousy rule for low hanging fruits. Most are catched by other rules in here but maybe these catch different versions."
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/09"
		hash = "d889da22893536d5965541c30896f4ed4fdf461d"
		hash = "10f4988a191774a2c6b85604344535ee610b844c1708602a355cf7e9c12c3605"
		hash = "7b6471774d14510cf6fa312a496eed72b614f6fc"
	strings:
		$pbs1 = "b374k shell" wide ascii
		$pbs2 = "b374k/b374k" wide ascii
		$pbs3 = "\"b374k" wide ascii
		$pbs4 = "$b374k" wide ascii
		$pbs5 = "b374k " wide ascii
		$pbs6 = "0de664ecd2be02cdd54234a0d1229b43" wide ascii
		$pbs7 = "pwnshell" wide ascii
		$pbs8 = "reGeorg" fullword wide ascii
		$pbs9 = "Georg says, 'All seems fine" fullword wide ascii
		$pbs10 = "My PHP Shell - A very simple web shell" wide ascii
		$pbs11 = "<title>My PHP Shell <?echo VERSION" wide ascii
		$pbs12 = "F4ckTeam" fullword wide ascii
		$pbs13 = "{\"_P\"./*-/*-*/\"OS\"./*-/*-*/\"T\"}" wide ascii
		$pbs14 = "/*-/*-*/\"" wide ascii
		$pbs15 = "MulCiShell" fullword wide ascii
		$pbs16 = "'ev'.'al'" wide ascii
		$pbs17 = "'e'.'val'" wide ascii
		$pbs18 = "e'.'v'.'a'.'l" wide ascii
		$pbs19 = "bas'.'e6'." wide ascii
		$pbs20 = "ba'.'se6'." wide ascii
		$pbs21 = "as'.'e'.'6'" wide ascii
		$pbs22 = "gz'.'inf'." wide ascii
		$pbs23 = "gz'.'un'.'c" wide ascii
		$pbs24 = "e'.'co'.'d" wide ascii
		$pbs25 = "cr\".\"eat" wide ascii
		$pbs26 = "un\".\"ct" wide ascii
		$pbs27 = "'c'.'h'.'r'" wide ascii
		$pbs28 = "\"ht\".\"tp\".\":/\"" wide ascii
		$pbs29 = "\"ht\".\"tp\".\"s:" wide ascii
		// crawler avoid string
		$pbs30 = "bot|spider|crawler|slurp|teoma|archive|track|snoopy|java|lwp|wget|curl|client|python|libwww" wide ascii
		$pbs31 = "'ev'.'al'" nocase wide ascii
		$pbs32 = "eval/*" nocase wide ascii
		$pbs34 = "assert/*" nocase wide ascii
		// <?=($pbs_=@$_GET[2]).@$_($_GET[1])?>
		$pbs35 = /@\$_GET\[\d\]\)\.@\$_\(\$_GET\[\d\]\)/ wide ascii
		$pbs36 = /@\$_GET\[\d\]\)\.@\$_\(\$_POST\[\d\]\)/ wide ascii
		$pbs37 = /@\$_POST\[\d\]\)\.@\$_\(\$_GET\[\d\]\)/ wide ascii
		$pbs38 = /@\$_POST\[\d\]\)\.@\$_\(\$_POST\[\d\]\)/ wide ascii
		$pbs39 = /@\$_REQUEST\[\d\]\)\.@\$_\(\$_REQUEST\[\d\]\)/ wide ascii
		$pbs40 = "'ass'.'ert'" nocase wide ascii
		$pbs41 = "${'_'.$_}['_'](${'_'.$_}['__'])" wide ascii
		$pbs42 = "array(\"find config.inc.php files\", \"find / -type f -name config.inc.php\")" wide ascii
		$pbs43 = "$_SERVER[\"\\x48\\x54\\x54\\x50" wide ascii
		$pbs44 = "'s'.'s'.'e'.'r'.'t'" nocase wide ascii
		$pbs45 = "'P'.'O'.'S'.'T'" wide ascii
		$pbs46 = "'G'.'E'.'T'" wide ascii
		$pbs47 = "'R'.'E'.'Q'.'U'" wide ascii
		$pbs48 = "se'.(32*2)"
		$front1 = "<?php eval(" nocase wide ascii
	condition:
		filesize < 500KB and 
		capa_php_old_safe and 
        (
            any of ( $pbs* ) or
            $front1 in (0..80)
        )
}


rule webshell_php_strings_susp {
	meta:
		description = "typical webshell strings, suspicious"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "0dd568dbe946b5aa4e1d33eab1decbd71903ea04"
		score = 50
	strings:
		$sstring1 = "eval(\"?>\"" nocase wide ascii
	condition:
		filesize < 700KB and 
        capa_php_old_safe and 
        ( 2 of ( $sstring* ) or ( 1 of ( $sstring* ) and capa_php_input ) ) and
        not php_false_positive
}


rule webshell_php_in_htaccess {
	meta:
		description = "Use Apache .htaccess to execute php code inside .htaccess"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "c026d4512a32d93899d486c6f11d1e13b058a713"
	strings:
		$hta = "AddType application/x-httpd-php .htaccess" wide ascii
	condition:
		filesize < 100KB and 
		$hta
}

rule webshell_php_func_in_get {
	meta:
		description = "Webshell which sends eval/assert via GET"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "ce739d65c31b3c7ea94357a38f7bd0dc264da052d4fd93a1eabb257f6e3a97a6"
		hash = "d870e971511ea3e082662f8e6ec22e8a8443ca79"
		date = "2021/01/09"
	strings:
		$sr0 = /\$_GET\[.{1,30}\]\(\$_GET\[/ wide ascii
		$sr1 = /\$_POST\[.{1,30}\]\(\$_GET\[/ wide ascii
		$sr2 = /\$_POST\[.{1,30}\]\(\$_POST\[/ wide ascii
		$sr3 = /\$_GET\[.{1,30}\]\(\$_POST\[/ wide ascii
		$sr4 = /\$_REQUEST\[.{1,30}\]\(\$_REQUEST\[/ wide ascii
		$sr5 = /\$_SERVER\[HTTP_.{1,30}\]\(\$_SERVER\[HTTP_/ wide ascii
	condition:
		filesize < 500KB and 
		any of ( $sr* ) and
        not php_false_positive
}


////        _    ____  ____           __     ______ ____   ____ ____  ___ ____ _____ 
////       / \  / ___||  _ \     _    \ \   / / __ ) ___| / ___|  _ \|_ _|  _ \_   _|
////      / _ \ \___ \| |_) |  _| |_   \ \ / /|  _ \___ \| |   | |_) || || |_) || |  
////     / ___ \ ___) |  __/  |_   _|   \ V / | |_) |__) | |___|  _ < | ||  __/ | |  
////    /_/   \_\____/|_|       |_|      \_/  |____/____/ \____|_| \_\___|_|    |_|  
                                                                             

private rule capa_asp {
	meta:
		description = "ASP short tag in first or last 1000 bytes or long ones anywhere"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/26"
	strings:
		$tagasp_short = "<%" wide ascii
		$tagasp_long1 = "72C24DD5-D70A-438B-8A42-98424B88AFB8" wide ascii
		$tagasp_long2 = "<% @language" wide ascii
	condition:
		$tagasp_short in ( 0..1000 ) or
		$tagasp_short in ( filesize-1000..filesize ) or
		any of ( $tagasp_long* )
}

private rule capa_asp_obfuscation_multi {
	meta:
		description = "ASP obfuscation functions which have to be used multiple times, e.g. for each character"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/06"
		score = 50
	strings:
		$o1 = "chr(" nocase wide ascii
		$o2 = "chr (" nocase wide ascii
		// not excactly a string function but also often used in obfuscation
		$o4 = "\\x1" wide ascii
		$o5 = "\\x2" wide ascii
		// just picking some random numbers because they should appear often enough in a long obfuscated blob and it's faster than a regex
		$o6 = "\\61" wide ascii
		$o7 = "\\44" wide ascii
		$o8 = "\\112" wide ascii
		$o9 = "\\120" wide ascii
	condition:
		(
			( #o1+#o2 ) > 50 or
			( #o4+#o5+#o6+#o7+#o8+#o9 ) > 20 
		) 
}

private rule capa_asp_payload {
	meta:
		description = "ASP eval versions"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/02/06"
	strings:
		$cpayload0 = "eval_r" fullword nocase wide ascii
		$cpayload1 = "eval" fullword nocase wide ascii
		$cpayload2 = "execute" fullword nocase wide ascii
		$cpayload3 = "WSCRIPT.SHELL" fullword nocase wide ascii
		$cpayload4 = "Scripting.FileSystemObject" fullword nocase wide ascii
		$cpayload5 = /ExecuteGlobal/ fullword nocase wide ascii
	condition:
		any of ( $cpayload* )
}

rule webshell_asp_obfuscated {
	meta:
		description = "ASP webshell obfuscated"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "7466d1434870eb151dbb415191fef2884dfade52"
		hash = "a6ab3695e46cd65610edb3c7780495d03a72c43d"
	condition:
		filesize < 100KB 
		and capa_asp
		and capa_asp_obfuscation_multi
		and capa_asp_payload
}


rule webshell_asp_generic_eval {
	meta:
		description = "Generic ASP webshell which uses any eval/exec function directly on user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "d6b96d844ac395358ee38d4524105d331af42ede"
		hash = "9be2088d5c3bfad9e8dfa2d7d7ba7834030c7407"
		hash = "a1df4cfb978567c4d1c353e988915c25c19a0e4a"
	strings:
		$payload_and_input0 = /eval_r[\t ]*\(Request\(/ nocase wide ascii
		$payload_and_input1 = /eval[\t ]*request\(/ nocase wide ascii
		$payload_and_input2 = /execute[\t \(]+request\(/ nocase wide ascii
		$payload_and_input4 = /ExecuteGlobal[\t ]*request\(/ nocase wide ascii
	condition:
		filesize < 100KB and 
		capa_asp and
		any of ( $payload_and_input* )
}

rule webshell_asp_nano {
	meta:
		description = "Generic ASP webshell which uses any eval/exec function"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/13"
		hash = "3b7910a499c603715b083ddb6f881c1a0a3a924d"
		hash = "990e3f129b8ba409a819705276f8fa845b95dad0"
		hash = "22345e956bce23304f5e8e356c423cee60b0912c"
		hash = "c84a6098fbd89bd085526b220d0a3f9ab505bcba"
	strings:
		$payload0 = "eval_r" fullword nocase wide ascii
		$payload1 = "eval" fullword nocase wide ascii
		$payload2 = "execute" fullword nocase wide ascii
		$payload3 = "WSCRIPT.SHELL" fullword nocase wide ascii
		$payload4 = "Scripting.FileSystemObject" fullword nocase wide ascii
		$payload5 = /ExecuteGlobal/ fullword nocase wide ascii
		$payload6 = "cmd /c" nocase wide ascii
		$payload7 = "cmd.exe" nocase wide ascii
        $fp1      = "eval a"
        $fp2      = "'Eval'"
        $fp3      = "Eval(\""
	condition:
		filesize < 200 and 
		capa_asp and 
		any of ($payload*) and
        not any of ( $fp* )
}

rule webshell_vbscript_nano_encoded {
	meta:
		description = "Generic small VBscript encoded webshell "
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "1c7fbad3c4ca83a70efcd19f34838cbde902c631"
		date = "2021/01/26"
	strings:
		$vb = "VBScript.Encode" nocase wide ascii
		$vb_encode1 = "<%#@~^" wide ascii
		$vb_encode2 = "<%=#@~^" wide ascii
	condition:
		$vb and
		( filesize < 200 and any of ( $vb_encode* ) ) or
		( filesize < 4000 and ( #vb_encode1 > 3 ) or ( #vb_encode2 > 3 ) ) or
		( filesize < 30KB and ( #vb_encode1 > 10 ) or ( #vb_encode2 > 10 ) ) 
}

rule webshell_asp_string {
	meta:
		description = "Generic ASP webshell strings"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/13"
		hash ="f72252b13d7ded46f0a206f63a1c19a66449f216"
	strings:
		$asp_string1 = "tseuqer lave" wide ascii
		$asp_string2 = ":eval request(" wide ascii
		$asp_string3 = ":eval request(" wide ascii
		$asp_string4 = "SItEuRl=\"http://www.zjjv.com\"" wide ascii
		$asp_string5 = "ServerVariables(\"HTTP_HOST\"),\"gov.cn\"" wide ascii
	condition:
		filesize < 200KB and 
		// not checking capa_asp
		any of ( $asp_string* )
}

rule webshell_asp_generic_tiny {
	meta:
		description = "Generic ASP webshell which uses any eval/exec function indirectly on user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "990e3f129b8ba409a819705276f8fa845b95dad0"
		hash = "52ce724580e533da983856c4ebe634336f5fd13a"
	strings:
		$input = "request" nocase wide ascii
		$payload0 = "eval_r" fullword nocase wide ascii
		$payload1 = "eval" fullword nocase wide ascii
		$payload2 = "execute" fullword nocase wide ascii
		$payload3 = "WSCRIPT.SHELL" fullword nocase wide ascii
		$write = "Scripting.FileSystemObject" fullword nocase wide ascii
	condition:
		capa_asp and 
		$input and 
		(
			filesize < 500 and 
			any of ($payload*)
		) or (
			filesize < 300 and 
			$write
		)
}

rule webshell_aspx_regeorg_csharp {
	meta:
		description = "Webshell regeorg aspx c# version"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		reference = "https://github.com/sensepost/reGeorg"
		hash = "c1f43b7cf46ba12cfc1357b17e4f5af408740af7ae70572c9cf988ac50260ce1"
		author = "Arnim Rupp"
		date = "2021/01/11"
	strings:
		$sainput = "Request.QueryString.Get" fullword nocase wide ascii
		$sa1 = "AddressFamily.InterNetwork" fullword nocase wide ascii
		$sa2 = "Response.AddHeader" fullword nocase wide ascii
		$sa3 = "Request.InputStream.Read" nocase wide ascii
		$sa4 = "Response.BinaryWrite" nocase wide ascii
		$sa5 = "Socket" nocase wide ascii
	condition:
		filesize < 300KB and
		capa_asp and
		all of ( $sa* )
}

rule webshell_csharp_generic {
	meta:
		description = "Webshell in c#"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "b6721683aadc4b4eba4f081f2bc6bc57adfc0e378f6d80e2bfa0b1e3e57c85c7"
		date = "2021/01/11"
	strings:
		$input_http = "Request." nocase wide ascii
		$input_form1 = "<asp:" nocase wide ascii
		$input_form2 = ".text" nocase wide ascii
		$exec_proc1 = "new Process" nocase wide ascii
		$exec_proc2 = "start(" nocase wide ascii
		$exec_shell1 = "cmd.exe" nocase wide ascii
		$exec_shell2 = "powershell.exe" nocase wide ascii
	condition:
		filesize < 300KB and 
		( 
			$input_http or all of ($input_form*) 
		) and 
		all of ($exec_proc*) and 
		any of ($exec_shell*)
}

rule webshell_asp_sharpyshell {
	meta:
		description = "SharPyShell is a tiny and obfuscated ASP.NET webshell that executes commands received by an encrypted channel compiling them in memory at runtime."
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		reference = "https://github.com/antonioCoco/SharPyShell"
		date = "2021/01/11"
		hash = "e826c4139282818d38dcccd35c7ae6857b1d1d01"
		hash = "e20e078d9fcbb209e3733a06ad21847c5c5f0e52"
		hash = "57f758137aa3a125e4af809789f3681d1b08ee5b"
	strings:
		$input = "Request.Form" nocase wide ascii
		$payload_reflection1 = "System.Reflection" nocase wide ascii
		$payload_reflection2 = "Assembly.Load" nocase wide ascii
		$payload_compile1 = "GenerateInMemory" nocase wide ascii
		$payload_compile2 = "CompileAssemblyFromSource" nocase wide ascii
		$payload_invoke = "Invoke" nocase wide ascii
	condition:
		filesize < 10KB and
		$input and 
		( 
			all of ( $payload_reflection* ) or 
			all of ( $payload_compile* ) 
		) and 
		$payload_invoke
}


//                 _ ____  ____
//                | / ___||  _ \
//             _  | \___ \| |_) |
//            | |_| |___) |  __/
//             \___/|____/|_|



private rule capa_jsp {
	meta:
		description = "capa JSP tag"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
	strings:
		$cjsp1 = "<%" ascii wide
		$cjsp2 = "<jsp:" ascii wide
		$cjsp3 = /language=[\"']java[\"\']/ ascii wide
		// JSF
		$cjsp4 = "/jstl/core" ascii wide
	condition:
		any of ( $cjsp* )
} 

private rule capa_jsp_input {
	meta:
		description = "capa JSP input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
	strings:
		// request.getParameter
		$input1 = "getParameter" fullword ascii wide
		// request.getHeaders
		$input2 = "getHeaders" fullword ascii wide
		$input3 = "getInputStream" fullword ascii wide
		$input4 = "getReader" fullword ascii wide
		$req1 = "request" fullword ascii wide
		$req2 = "HttpServletRequest" fullword ascii wide
		$req3 = "getRequest" fullword ascii wide
	condition:
		any of ( $input* ) and
		any of ( $req* )
} 

rule webshell_jsp_regeorg {
	meta:
		description = "Webshell regeorg JSP version"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		reference = "https://github.com/sensepost/reGeorg"
		hash = "6db49e43722080b5cd5f07e058a073ba5248b584"
		author = "Arnim Rupp"
		date = "2021/01/24"
	strings:
		$jgeorg1 = "request" fullword wide ascii
		$jgeorg2 = "getHeader" fullword wide ascii
		$jgeorg3 = "X-CMD" fullword wide ascii
		$jgeorg4 = "X-STATUS" fullword wide ascii
		$jgeorg5 = "socket" fullword wide ascii
		$jgeorg6 = "FORWARD" fullword wide ascii
	condition:
		filesize < 300KB and 
		capa_jsp and 
		all of ( $jgeorg* )
}

rule webshell_jsp_http_proxy {
	meta:
		description = "Webshell JSP HTTP proxy"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		hash = "2f9b647660923c5262636a5344e2665512a947a4"
		author = "Arnim Rupp"
		date = "2021/01/24"
	strings:
		$jh1 = "OutputStream" fullword wide ascii
		$jh2 = "InputStream"  wide ascii
		$jh3 = "BufferedReader" fullword wide ascii
		$jh4 = "HttpRequest" fullword wide ascii
		$jh5 = "openConnection" fullword wide ascii
		$jh6 = "getParameter" fullword wide ascii
	condition:
		filesize < 10KB and 
		capa_jsp and 
		all of ( $jh* )
}

rule webshell_jsp_writer_nano {
	meta:
		description = "JSP file writer"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "ac91e5b9b9dcd373eaa9360a51aa661481ab9429"
		hash = "c718c885b5d6e29161ee8ea0acadb6e53c556513"
	strings:
		$payload1 = ".write" wide ascii
		$payload2 = "getBytes" fullword wide ascii
	condition:
		filesize < 200 and 
		capa_jsp_input and 
		capa_jsp and 
		2 of ( $payload* )
}

rule webshell_jsp_generic_tiny {
	meta:
		description = "Generic JSP webshell tiny"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "8fd343db0442136e693e745d7af1018a99b042af"
		hash = "ee9408eb923f2d16f606a5aaac7e16b009797a07"
	strings:
		$payload1 = "ProcessBuilder" fullword wide ascii
		$payload2 = "URLClassLoader" fullword wide ascii
		// Runtime.getRuntime().exec(
		$payload_rt1 = "Runtime" fullword wide ascii
		$payload_rt2 = "getRuntime" fullword wide ascii
		$payload_rt3 = "exec" fullword wide ascii
	condition:
		filesize < 8000 and 
		capa_jsp and
		capa_jsp_input and
		( 
			1 of ( $payload* ) or
			all of ( $payload_rt* )
		)
}

rule webshell_jsp_generic {
	meta:
		description = "Generic JSP webshell"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "4762f36ca01fb9cda2ab559623d2206f401fc0b1"
		hash = "bdaf9279b3d9e07e955d0ce706d9c42e4bdf9aa1"
	strings:
		$payload1 = "ProcessBuilder" fullword ascii wide
		$payload2 = "processCmd" fullword ascii wide
		// Runtime.getRuntime().exec(
		$rt_payload1 = "Runtime" fullword ascii wide
		$rt_payload2 = "getRuntime" fullword ascii wide
		$rt_payload3 = "exec" fullword ascii wide
		$susp0 = "cmd" fullword nocase ascii wide
		$susp1 = "command" fullword nocase ascii wide
		$susp2 = "shell" fullword nocase ascii wide
		$susp3 = "download" fullword nocase ascii wide
		$susp4 = "upload" fullword nocase ascii wide
		$susp5 = "Execute" fullword nocase ascii wide
	condition:
		filesize < 300KB and 
        not uint16(0) == 0x5a4d and 
        // fp on jar with zero compression
        not uint16(0) == 0x4b50 and 
		capa_jsp and  
		capa_jsp_input and  
		any of ( $susp* ) and
		( 
			1 of ( $payload* ) or
			all of ( $rt_payload* )
		)
}

rule webshell_jsp_generic_base64 {
	meta:
		description = "Generic JSP webshell with base64 encoded payload"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "8b5fe53f8833df3657ae2eeafb4fd101c05f0db0"
		hash = "1b916afdd415dfa4e77cecf47321fd676ba2184d"
	strings:
		// Runtime
		$one1 = "SdW50aW1l" wide ascii
		$one2 = "J1bnRpbW" wide ascii
		$one3 = "UnVudGltZ" wide ascii
		$one4 = "IAdQBuAHQAaQBtAGUA" wide ascii
		$one5 = "SAHUAbgB0AGkAbQBlA" wide ascii
		$one6 = "UgB1AG4AdABpAG0AZQ" wide ascii
		// exec
		$two1 = "leGVj" wide ascii
		$two2 = "V4ZW" wide ascii
		$two3 = "ZXhlY" wide ascii
		$two4 = "UAeABlAGMA" wide ascii
		$two5 = "lAHgAZQBjA" wide ascii
		$two6 = "ZQB4AGUAYw" wide ascii
		// ScriptEngineFactory
		$three1 = "TY3JpcHRFbmdpbmVGYWN0b3J5" wide ascii
		$three2 = "NjcmlwdEVuZ2luZUZhY3Rvcn" wide ascii
		$three3 = "U2NyaXB0RW5naW5lRmFjdG9ye" wide ascii
		$three4 = "MAYwByAGkAcAB0AEUAbgBnAGkAbgBlAEYAYQBjAHQAbwByAHkA" wide ascii
		$three5 = "TAGMAcgBpAHAAdABFAG4AZwBpAG4AZQBGAGEAYwB0AG8AcgB5A" wide ascii
		$three6 = "UwBjAHIAaQBwAHQARQBuAGcAaQBuAGUARgBhAGMAdABvAHIAeQ" wide ascii

	condition:
		capa_jsp and
		filesize < 300KB and (
			any of ( $one* ) and any of ( $two* ) 
			or any of ( $three* ) 
		)

}

rule webshell_jsp_generic_processbuilder {
	meta:
		description = "Generic JSP webshell which uses processbuilder to execute user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "82198670ac2072cd5c2853d59dcd0f8dfcc28923"
		hash = "c05a520d96e4ebf9eb5c73fc0fa446ceb5caf343"
	strings:
		$exec = "ProcessBuilder" fullword wide ascii
		$start = "start" fullword wide ascii
	condition:
		filesize < 2000 and 
		capa_jsp_input and 
		$exec and 
		$start
}

rule webshell_jsp_generic_reflection {
	meta:
		description = "Generic JSP webshell which uses reflection to execute user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "62e6c6065b5ca45819c1fc049518c81d7d165744"
	strings:
		$ws_exec = "invoke" fullword wide ascii
		$ws_class = "Class" fullword wide ascii
		$fp = "SOAPConnection"
	condition:
		filesize < 10KB and 
		all of ( $ws_* ) and
		capa_jsp and
		capa_jsp_input and
		not $fp
}

rule webshell_jsp_generic_classloader {
	meta:
		description = "Generic JSP webshell which uses classloader to execute user input"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		hash = "6b546e78cc7821b63192bb8e087c133e8702a377d17baaeb64b13f0dd61e2347"
		date = "2021/01/07"
	strings:
		$exec = "extends ClassLoader" wide ascii
		$class = "defineClass" fullword wide ascii
	condition:
		filesize < 10KB and 
		capa_jsp and
		capa_jsp_input and
		$exec and
		$class
}

rule webshell_jsp_generic_encoded_shell {
	meta:
		description = "Generic JSP webshell which contains cmd or /bin/bash encoded in ascii ord"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/07"
		hash = "3eecc354390d60878afaa67a20b0802ce5805f3a9bb34e74dd8c363e3ca0ea5c"
	strings:
		$sj0 = /{ ?47, 98, 105, 110, 47, 98, 97, 115, 104/ wide ascii
		$sj1 = /{ ?99, 109, 100}/ wide ascii
		$sj2 = /{ ?99, 109, 100, 46, 101, 120, 101/ wide ascii
		$sj3 = /{ ?47, 98, 105, 110, 47, 98, 97/ wide ascii
		$sj4 = /{ ?106, 97, 118, 97, 46, 108, 97, 110/ wide ascii
		$sj5 = /{ ?101, 120, 101, 99 }/ wide ascii
		$sj6 = /{ ?103, 101, 116, 82, 117, 110/ wide ascii
	condition:
		filesize < 300KB and 
		any of ( $sj* )
}

rule webshell_jsp_netspy {
	meta:
		description = "JSP netspy webshell"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "94d1aaabde8ff9b4b8f394dc68caebf981c86587"
		hash = "3870b31f26975a7cb424eab6521fc9bffc2af580"
	strings:
		$scan1 = "scan" nocase wide ascii
		$scan2 = "port" nocase wide ascii
		$scan3 = "web" fullword nocase wide ascii
		$scan4 = "proxy" fullword nocase wide ascii
		$scan5 = "http" fullword nocase wide ascii
		$scan6 = "https" fullword nocase wide ascii
		$write1 = "os.write" fullword wide ascii
		$write2 = "FileOutputStream" fullword wide ascii
		$write3 = "PrintWriter" fullword wide ascii
		$http = "java.net.HttpURLConnection" fullword wide ascii
	condition:
		filesize < 30KB and 
		capa_jsp and
		capa_jsp_input and
		4 of ( $scan* ) and 
		1 of ( $write* ) and 
		$http
}

rule webshell_jsp_by_string {
	meta:
		description = "JSP Webshells which contain unique strings, lousy rule for low hanging fruits. Most are catched by other rules in here but maybe these catch different versions."
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/09"
		hash = "e9060aa2caf96be49e3b6f490d08b8a996c4b084"
		hash = "4c2464503237beba54f66f4a099e7e75028707aa"
		hash = "06b42d4707e7326aff402ecbb585884863c6351a"
	strings:
		$jstring1 = "<title>Boot Shell</title>" wide ascii
		$jstring2 = "String oraPWD=\"" wide ascii
		$jstring3 = "Owned by Chinese Hackers!" wide ascii
		$jstring4 = "AntSword JSP" wide ascii
		$jstring5 = "JSP Webshell</" wide ascii
		$jstring6 = "motoME722remind2012" wide ascii
		$jstring7 = "EC(getFromBase64(toStringHex(request.getParameter(\"password" wide ascii
		$jstring8 = "http://jmmm.com/web/index.jsp" wide ascii
		$jstring9 = "list.jsp = Directory & File View" wide ascii
		$jstring10 = "jdbcRowSet.setDataSourceName(request.getParameter(" wide ascii
		$jstring11 = "Mr.Un1k0d3r RingZer0 Team" wide ascii
		$jstring12 = "MiniWebCmdShell" fullword wide ascii
		$jstring13 = "pwnshell.jsp" fullword wide ascii
		$jstring14 = "session set &lt;key&gt; &lt;value&gt; [class]<br>"  wide ascii
	condition:
		filesize < 100KB and 
		capa_jsp and 
		any of ( $jstring* )
}


rule webshell_jsp_input_upload_write {
	meta:
		description = "JSP uploader which gets input, writes files and contains \"upload\""
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "ef98ca135dfb9dcdd2f730b18e883adf50c4ab82"
		hash = "583231786bc1d0ecca7d8d2b083804736a3f0a32"
		hash = "19eca79163259d80375ebebbc440b9545163e6a3"
	strings:
		$upload = "upload" nocase wide ascii
		$write1 = "os.write" fullword wide ascii
		$write2 = "FileOutputStream" fullword wide ascii
	condition:
		filesize < 10KB and 
		capa_jsp and 
		capa_jsp_input and 
		$upload and 
		1 of ( $write* )
}



//              _      
//    _ __ ___ (_)_  __
//   | '_ ` _ \| \ \/ /
//   | | | | | | |>  < 
//   |_| |_| |_|_/_/\_\
                  
rule webshell_generic_os_strings {
	meta:
		description = "typical webshell strings"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/12"
		hash = "cd14346f158a616ca9a79edf07e3eb3acc84afae"
		hash = "543b1760d424aa694de61e6eb6b3b959dee746c2"
		score = 50
	strings:
		$fp1 = "http://evil.com/" wide ascii
		$fp2 = "denormalize('/etc/shadow" wide ascii
	condition:
		filesize < 140KB and 
		( capa_asp or capa_php_old_safe or capa_jsp ) and 
		capa_os_strings and
		not any of ( $fp* )
}

//                       _      _                 
//   ___ _   _ ___ _ __ (_) ___(_) ___  _   _ ___ 
//  / __| | | / __| '_ \| |/ __| |/ _ \| | | / __|
//  \__ \ |_| \__ \ |_) | | (__| | (_) | |_| \__ \
//  |___/\__,_|___/ .__/|_|\___|_|\___/ \__,_|___/
//                |_|                             

// uncomment to find suspicous files but also more false positives

/* 

rule webshell_jsp_input_write_nano {
	meta:
		description = "Suspicious: JSP file writer: input and write"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "108c5eeb85f9a2bfb896a1c42a00978f5770e195"
		hash = "30dae7c1473b767d44f8e30600891a524ac8dea0"
		hash = "22609061c167befd5c32b0798eb52e89d68c74ef"
		score = 40
	strings:
		$write1 = "os.write" fullword wide ascii
		$write2 = "FileOutputStream" fullword wide ascii
	condition:
		filesize < 1500 and 
		capa_jsp and 
		capa_jsp_input and 
		1 of ( $write* )
}

rule suspicous_webshell_input_password_sql {
	meta:
		description = "JSP SQL tool with password"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/24"
		hash = "a20dcd6bfafb313da2ed9e8bf006b0cf6026084c"
		hash = "e6a33e17569749612b06e3001544b2f04345d5ae"
	strings:
		$pwd1 = "password" nocase wide ascii
		$pwd2 = "pwd" nocase wide ascii
		$sql1 = "jdbc" nocase wide ascii
		$sql2 = "select" fullword nocase wide ascii
		$sql3 = "sql" fullword nocase wide ascii
		$sql4 = "createStatement" fullword nocase wide ascii

	condition:
		filesize < 20KB and 
		1 of ( $pwd* ) and 
		3 of ( $sql* ) and 
		capa_jsp_input
}

rule webshell_php_generic_nano_payload_or_callback {
	meta:
		description = "php webshell having some method to execute code, no check where it comes from. restricted to small files or would give lots of false positives"
		license = "https://creativecommons.org/licenses/by-nc/4.0/"
		author = "Arnim Rupp"
		date = "2021/01/14"
		hash = "29c80a36f0919c39fb0de4732c506da5eee89783"
		hash = "76e3491998b76f83b570a4bb66e65dd0de629e9a"
		score = 40
	strings:
		$fp1 = "__DIR__" wide ascii
	condition:
		filesize < 100 and 
		capa_php and
		( capa_php_payload or capa_php_callback ) and not
		any of ( $fp* )
}

*/

