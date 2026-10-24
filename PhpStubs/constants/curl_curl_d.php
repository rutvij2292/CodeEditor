<?php

/**
 * A bitmask consisting of one or more of
 * CURLSSH_AUTH_PUBLICKEY,
 * CURLSSH_AUTH_PASSWORD,
 * CURLSSH_AUTH_HOST,
 * CURLSSH_AUTH_KEYBOARD. Set to
 * CURLSSH_AUTH_ANY to let libcurl pick one.
 */
const CURLOPT_SSH_AUTH_TYPES = 151;

/**
 * TRUE tells the library to perform all the required proxy authentication
 * and connection setup, but no data transfer. This option is implemented for
 * HTTP, SMTP and POP3.
 * @since 5.5
 */
const CURLOPT_CONNECT_ONLY = 141;

/**
 * With the CURLOPT_FOLLOWLOCATION option disabled:
 * redirect URL found in the last transaction, that should be requested manually next.
 * With the CURLOPT_FOLLOWLOCATION option enabled:
 * this is empty. The redirect URL in this case is available in CURLINFO_EFFECTIVE_URL
 * @since 5.3
 */
const CURLINFO_REDIRECT_URL = 1048607;

/**
 * IP address of the most recent connection
 * @since 5.4
 */
const CURLINFO_PRIMARY_IP = 1048608;

/**
 * Destination port of the most recent connection
 * @since 5.4
 */
const CURLINFO_PRIMARY_PORT = 2097192;

/**
 * Local (source) IP address of the most recent connection
 * @since 5.4
 */
const CURLINFO_LOCAL_IP = 1048617;

/**
 * Local (source) port of the most recent connection
 * @since 5.4
 */
const CURLINFO_LOCAL_PORT = 2097194;

/**
 * A result of curl_share_init(). Makes the cURL handle to use the data from the shared handle.
 * @since 5.5
 */
const CURLOPT_SHARE = 10100;

/**
 * Allows an application to select what kind of IP addresses to use when resolving host names.
 * This is only interesting when using host names that resolve addresses using more than one version of IP,
 * possible values are CURL_IPRESOLVE_WHATEVER, CURL_IPRESOLVE_V4, CURL_IPRESOLVE_V6, by default CURL_IPRESOLVE_WHATEVER.
 */
const CURLOPT_IPRESOLVE = 113;

/**
 * Value for the CURLOPT_IPRESOLVE option.
 * Default, resolves addresses to all IP versions that your system allows.
 */
const CURL_IPRESOLVE_WHATEVER = 0;

/**
 * Value for the CURLOPT_IPRESOLVE option.
 * Resolve to IPv4 addresses.
 */
const CURL_IPRESOLVE_V4 = 1;

/**
 * Value for the CURLOPT_IPRESOLVE option.
 * Resolve to IPv6 addresses.
 */
const CURL_IPRESOLVE_V6 = 2;

/**
 * TRUE to use a global DNS cache. This option is not thread-safe.
 * It is conditionally enabled by default if PHP is built for non-threaded use (CLI, FCGI, Apache2-Prefork, etc.).
 */
const CURLOPT_DNS_USE_GLOBAL_CACHE = 91;

/**
 * The number of seconds to keep DNS entries in memory.
 * This option is set to 120 (2 minutes) by default.
 */
const CURLOPT_DNS_CACHE_TIMEOUT = 92;

/**
 * An alternative port number to connect to.
 */
const CURLOPT_PORT = 3;

/**
 * The file that the transfer should be written to. The default is STDOUT (the browser window).
 */
const CURLOPT_FILE = 10001;

/**
 * Custom pointer passed to the read callback.
 * If you use the CURLOPT_READFUNCTION option, this is the pointer you'll get as input in the 4th argument to the callback.
 */
const CURLOPT_READDATA = 10009;

/**
 * The file that the transfer should be read from when uploading.
 */
const CURLOPT_INFILE = 10009;

/**
 * The expected size, in bytes, of the file when uploading a file to a remote site.
 * Note that using this option will not stop libcurl from sending more data, as exactly what is sent depends on CURLOPT_READFUNCTION.
 */
const CURLOPT_INFILESIZE = 14;

/**
 * The URL to fetch. This can also be set when initializing a session with curl_init().
 */
const CURLOPT_URL = 10002;

/**
 * The HTTP proxy to tunnel requests through.
 */
const CURLOPT_PROXY = 10004;

/**
 * TRUE to output verbose information.
 * Writes output to STDERR, or the file specified using CURLOPT_STDERR.
 */
const CURLOPT_VERBOSE = 41;

/**
 * TRUE to include the header in the output.
 */
const CURLOPT_HEADER = 42;

/**
 * An array of HTTP header fields to set, in the format array('Content-type: text/plain', 'Content-length: 100')
 */
const CURLOPT_HTTPHEADER = 10023;

/**
 * TRUE to disable the progress meter for cURL transfers.
 */
const CURLOPT_NOPROGRESS = 43;

/**
 * A callback accepting five parameters.
 * The first is the cURL resource,
 * the second is the total number of bytes expected to be downloaded in this transfer,
 * the third is the number of bytes downloaded so far,
 * the fourth is the total number of bytes expected to be uploaded in this transfer,
 * and the fifth is the number of bytes uploaded so far.
 * (The callback is only called when the CURLOPT_NOPROGRESS option is set to FALSE.)
 * Return a non-zero value to abort the transfer. In which case, the transfer will set a CURLE_ABORTED_BY_CALLBACK error.
 * @since 5.3
 */
const CURLOPT_PROGRESSFUNCTION = 20056;

/**
 * TRUE to exclude the body from the output. Request method is then set to HEAD. Changing this to FALSE does not change it to GET.
 */
const CURLOPT_NOBODY = 44;

/**
 * TRUE to fail verbosely if the HTTP code returned is greater than or equal to 400.
 * The default behavior is to return the page normally, ignoring the code.
 */
const CURLOPT_FAILONERROR = 45;

/**
 * TRUE to prepare for an upload.
 */
const CURLOPT_UPLOAD = 46;

/**
 * TRUE to do a regular HTTP POST.
 * This POST is the normal application/x-www-form-urlencoded kind, most commonly used by HTML forms.
 */
const CURLOPT_POST = 47;

/**
 * TRUE to only list the names of an FTP directory.
 */
const CURLOPT_FTPLISTONLY = 48;

/**
 * TRUE to append to the remote file instead of overwriting it.
 */
const CURLOPT_FTPAPPEND = 50;

/**
 * TRUE to scan the ~/.netrc file to find a username and password for the remote site that a connection is being established with.
 */
const CURLOPT_NETRC = 51;

/**
 * A bitmask of 1 (301 Moved Permanently), 2 (302 Found) and 4 (303 See Other) if the HTTP POST method should be maintained
 * when CURLOPT_FOLLOWLOCATION is set and a specific type of redirect occurs.
 * @since 5.3
 */
const CURLOPT_POSTREDIR = 161;

/**
 * TRUE to output SSL certification information to STDERR on secure transfers.
 * Requires CURLOPT_VERBOSE to be on to have an effect.
 * @since 5.3
 */
const CURLOPT_CERTINFO = 172;

/**
 * An alias of CURLOPT_TRANSFERTEXT. Use that instead.
 */
const CURLOPT_FTPASCII = -1;

/**
 * TRUE to be completely silent with regards to the cURL functions.
 * @deprecated use CURLOPT_RETURNTRANSFER instead since cURL 7.15.5
 */
const CURLOPT_MUTE = -1;

/**
 * Bitmask of CURLPROTO_* values. If used, this bitmask limits what protocols libcurl may use in the transfer.
 * This allows you to have a libcurl built to support a wide range of protocols but still limit specific transfers
 * to only be allowed to use a subset of them.
 * By default libcurl will accept all protocols it supports. See also CURLOPT_REDIR_PROTOCOLS.
 * Valid protocol options are:
 * CURLPROTO_HTTP, CURLPROTO_HTTPS, CURLPROTO_FTP, CURLPROTO_FTPS, CURLPROTO_SCP, CURLPROTO_SFTP,
 * CURLPROTO_TELNET, CURLPROTO_LDAP, CURLPROTO_LDAPS, CURLPROTO_DICT, CURLPROTO_FILE, CURLPROTO_TFTP,
 * CURLPROTO_ALL
 * @since 5.2
 */
const CURLOPT_PROTOCOLS = 181;

/**
 * Bitmask of CURLPROTO_* values. If used, this bitmask limits what protocols libcurl may use in a transfer
 * that it follows to in a redirect when CURLOPT_FOLLOWLOCATION is enabled.
 * This allows you to limit specific transfers to only be allowed to use a subset of protocols in redirections.
 * By default libcurl will allow all protocols except for FILE and SCP.
 * This is a difference compared to pre-7.19.4 versions which unconditionally would follow to all protocols supported.
 * See also CURLOPT_PROTOCOLS for protocol constant values.
 * @since 5.2
 */
const CURLOPT_REDIR_PROTOCOLS = 182;

/**
 * If a download exceeds this speed (counted in bytes per second) on cumulative average during the transfer,
 * the transfer will pause to keep the average rate less than or equal to the parameter value.
 * Defaults to unlimited speed.
 * @since 5.4
 */
const CURLOPT_MAX_RECV_SPEED_LARGE = 30146;

/**
 * If an upload exceeds this speed (counted in bytes per second) on cumulative average during the transfer,
 * the transfer will pause to keep the average rate less than or equal to the parameter value.
 * Defaults to unlimited speed.
 * @since 5.4
 */
const CURLOPT_MAX_SEND_SPEED_LARGE = 30145;

/**
 * A callback accepting three parameters.
 * The first is the cURL resource, the second is a string containing a password prompt, and the third is the maximum password length.
 * Return the string containing the password.
 */
const CURLOPT_PASSWDFUNCTION = -1;

/**
 * TRUE to follow any "Location: " header that the server sends as part of the HTTP header
 * (note this is recursive, PHP will follow as many "Location: " headers that it is sent, unless CURLOPT_MAXREDIRS is set).
 * This constant is not available when open_basedir
 * or safe_mode are enabled.
 */
const CURLOPT_FOLLOWLOCATION = 52;

/**
 * TRUE to HTTP PUT a file. The file to PUT must be set with CURLOPT_INFILE and CURLOPT_INFILESIZE.
 */
const CURLOPT_PUT = 54;

/**
 * A username and password formatted as "[username]:[password]" to use for the connection.
 */
const CURLOPT_USERPWD = 10005;

/**
 * A username and password formatted as "[username]:[password]" to use for the connection to the proxy.
 */
const CURLOPT_PROXYUSERPWD = 10006;

/**
 * Range(s) of data to retrieve in the format "X-Y" where X or Y are optional.
 * HTTP transfers also support several intervals, separated with commas in the format "X-Y,N-M".
 */
const CURLOPT_RANGE = 10007;

/**
 * The maximum number of seconds to allow cURL functions to execute.
 */
const CURLOPT_TIMEOUT = 13;

/**
 * The maximum number of milliseconds to allow cURL functions to execute.
 * If libcurl is built to use the standard system name resolver,
 * that portion of the connect will still use full-second resolution for timeouts with a minimum timeout allowed of one second.
 * @since 5.2
 */
const CURLOPT_TIMEOUT_MS = 155;

/**
 * The full data to post in a HTTP "POST" operation.
 * To post a file, prepend a filename with @ and use the full path.
 * The filetype can be explicitly specified by following the filename with the type in the format ';type=mimetype'.
 * This parameter can either be passed
 * as a urlencoded string like 'para1=val1¶2=val2&...'
 * or as an array with the field name as key and field data as value.
 * If value is an array, the Content-Type header will be set to multipart/form-data.
 * As of PHP 5.2.0, value must be an array if files are passed to this option with the @ prefix.
 * As of PHP 5.5.0, the @ prefix is deprecated and files can be sent using CURLFile.
 * The @ prefix can be disabled for safe passing of values ...
 */
const CURLOPT_POSTFIELDS = 10015;

/**
 * The contents of the "Referer: " header to be used in a HTTP request.
 */
const CURLOPT_REFERER = 10016;

/**
 * A string containing 32 hexadecimal digits.
 * The string should be the MD5 checksum of the remote host's public key, and libcurl will reject the connection to the host unless the md5sums match.
 * This option is only for SCP and SFTP transfers.
 */
const CURLOPT_SSH_HOST_PUBLIC_KEY_MD5 = 10162;

/**
 * The file name for your public key. If not used, libcurl defaults to $HOME/.ssh/id_dsa.pub
 * if the HOME environment variable is set, and just "id_dsa.pub" in the current directory if HOME is not set.
 */
const CURLOPT_SSH_PUBLIC_KEYFILE = 10152;

/**
 * The file name for your private key. If not used, libcurl defaults to $HOME/.ssh/id_dsa
 * if the HOME environment variable is set, and just "id_dsa" in the current directory if HOME is not set.
 * If the file is password-protected, set the password with CURLOPT_KEYPASSWD.
 */
const CURLOPT_SSH_PRIVATE_KEYFILE = 10153;

/**
 * The contents of the "User-Agent: " header to be used in a HTTP request.
 */
const CURLOPT_USERAGENT = 10018;

/**
 * The value which will be used to get the IP address to use for the FTP "PORT" instruction.
 * The "PORT" instruction tells the remote server to connect to our specified IP address.
 * The string may be a plain IP address, a hostname, a network interface name (under Unix),
 * or just a plain '-' to use the systems default IP address.
 */
const CURLOPT_FTPPORT = 10017;

/**
 * TRUE to first try an EPSV command for FTP transfers before reverting back to PASV. Set to FALSE to disable EPSV.
 */
const CURLOPT_FTP_USE_EPSV = 85;

/**
 * The transfer speed, in bytes per second, that the transfer should be below during the count of CURLOPT_LOW_SPEED_TIME seconds
 * before PHP considers the transfer too slow and aborts.
 */
const CURLOPT_LOW_SPEED_LIMIT = 19;

/**
 * The number of seconds the transfer speed should be below CURLOPT_LOW_SPEED_LIMIT
 * before PHP considers the transfer too slow and aborts.
 */
const CURLOPT_LOW_SPEED_TIME = 20;

/**
 * The offset, in bytes, to resume a transfer from.
 */
const CURLOPT_RESUME_FROM = 21;

/**
 * The contents of the "Cookie: " header to be used in the HTTP request.
 * Note that multiple cookies are separated with a semicolon followed by a space (e.g., "fruit=apple; colour=red")
 */
const CURLOPT_COOKIE = 10022;

/**
 * TRUE to mark this as a new cookie "session".
 * It will force libcurl to ignore all cookies it is about to load that are "session cookies" from the previous session.
 * By default, libcurl always stores and loads all cookies, independent if they are session cookies or not.
 * Session cookies are cookies without expiry date and they are meant to be alive and existing for this "session" only.
 */
const CURLOPT_COOKIESESSION = 96;

/**
 * TRUE to automatically set the Referer: field in requests where it follows a Location: redirect.
 */
const CURLOPT_AUTOREFERER = 58;

/**
 * The name of a file containing a PEM formatted certificate.
 */
const CURLOPT_SSLCERT = 10025;

/**
 * The password required to use the CURLOPT_SSLCERT certificate.
 */
const CURLOPT_SSLCERTPASSWD = 10026;

/**
 * The file that the header part of the transfer is written to.
 */
const CURLOPT_WRITEHEADER = 10029;

/**
 * 1 to check the existence of a common name in the SSL peer certificate. (Deprecated)
 * 2 to check the existence of a common name and also verify that it matches the hostname provided.
 * 0 to not check the names. In production environments the value of this option should be kept at 2 (default value).
 */
const CURLOPT_SSL_VERIFYHOST = 81;

/**
 * The name of the file containing the cookie data.
 * The cookie file can be in Netscape format, or just plain HTTP-style headers dumped into a file.
 * If the name is an empty string, no cookies are loaded, but cookie handling is still enabled.
 */
const CURLOPT_COOKIEFILE = 10031;

/**
 * One of CURL_SSLVERSION_DEFAULT (0), CURL_SSLVERSION_TLSv1 (1), CURL_SSLVERSION_SSLv2 (2), CURL_SSLVERSION_SSLv3 (3),
 * CURL_SSLVERSION_TLSv1_0 (4), CURL_SSLVERSION_TLSv1_1 (5) or CURL_SSLVERSION_TLSv1_2 (6).
 * The maximum TLS version can be set by using one of the CURL_SSLVERSION_MAX_* constants.
 * It is also possible to OR one of the CURL_SSLVERSION_* constants with one of the CURL_SSLVERSION_MAX_* constants.
 * CURL_SSLVERSION_MAX_DEFAULT (the maximum version supported by the library), CURL_SSLVERSION_MAX_TLSv1_0, CURL_SSLVERSION_MAX_TLSv1_1,
 * CURL_SSLVERSION_MAX_TLSv1_2, or CURL_SSLVERSION_MAX_TLSv1_3.
 */
const CURLOPT_SSLVERSION = 32;

/**
 * Value for the CURLOPT_SSLVERSION option.
 */
const CURL_SSLVERSION_DEFAULT = 0;

/**
 * Value for the CURLOPT_SSLVERSION option.
 */
const CURL_SSLVERSION_TLSv1 = 1;

/**
 * Value for the CURLOPT_SSLVERSION option.
 */
const CURL_SSLVERSION_SSLv2 = 2;

/**
 * Value for the CURLOPT_SSLVERSION option.
 */
const CURL_SSLVERSION_SSLv3 = 3;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 5.6
 * @since 5.5
 */
const CURL_SSLVERSION_TLSv1_0 = 4;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 5.6
 * @since 5.5
 */
const CURL_SSLVERSION_TLSv1_1 = 5;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 5.6
 * @since 5.5
 */
const CURL_SSLVERSION_TLSv1_2 = 6;

/**
 * How CURLOPT_TIMEVALUE is treated.
 * Use CURL_TIMECOND_IFMODSINCE to return the page only if it has been modified since the time specified in CURLOPT_TIMEVALUE.
 * If it hasn't been modified, a "304 Not Modified" header will be returned assuming CURLOPT_HEADER is TRUE.
 * Use CURL_TIMECOND_IFUNMODSINCE for the reverse effect.
 * CURL_TIMECOND_IFMODSINCE is the default.
 */
const CURLOPT_TIMECONDITION = 33;

/**
 * The time in seconds since January 1st, 1970.
 * The time will be used by CURLOPT_TIMECONDITION. By default, CURL_TIMECOND_IFMODSINCE is used.
 */
const CURLOPT_TIMEVALUE = 34;

/**
 * A custom request method to use instead of "GET" or "HEAD" when doing a HTTP request.
 * This is useful for doing "DELETE" or other, more obscure HTTP requests.
 * Valid values are things like "GET", "POST", "CONNECT" and so on; i.e. Do not enter a whole HTTP request line here.
 * For instance, entering "GET /index.html HTTP/1.0\r\n\r\n" would be incorrect.
 */
const CURLOPT_CUSTOMREQUEST = 10036;

/**
 * An alternative location to output errors to instead of STDERR.
 */
const CURLOPT_STDERR = 10037;

/**
 * TRUE to use ASCII mode for FTP transfers.
 * For LDAP, it retrieves data in plain text instead of HTML.
 * On Windows systems, it will not set STDOUT to binary mode.
 */
const CURLOPT_TRANSFERTEXT = 53;

/**
 * TRUE to return the transfer as a string of the return value of curl_exec() instead of outputting it directly.
 */
const CURLOPT_RETURNTRANSFER = 19913;

/**
 * An array of FTP commands to execute on the server prior to the FTP request.
 */
const CURLOPT_QUOTE = 10028;

/**
 * An array of FTP commands to execute on the server after the FTP request has been performed.
 */
const CURLOPT_POSTQUOTE = 10039;

/**
 * The name of the outgoing network interface to use. This can be an interface name, an IP address or a host name.
 */
const CURLOPT_INTERFACE = 10062;

/**
 * The KRB4 (Kerberos 4) security level.
 * Any of the following values (in order from least to most powerful) are valid: "clear", "safe", "confidential", "private".
 * If the string does not match one of these, "private" is used.
 * Setting this option to NULL will disable KRB4 security. Currently KRB4 security only works with FTP transactions.
 */
const CURLOPT_KRB4LEVEL = 10063;

/**
 * TRUE to tunnel through a given HTTP proxy.
 */
const CURLOPT_HTTPPROXYTUNNEL = 61;

/**
 * TRUE to attempt to retrieve the modification date of the remote document.
 * This value can be retrieved using the CURLINFO_FILETIME option with curl_getinfo().
 */
const CURLOPT_FILETIME = 69;

/**
 * A callback accepting two parameters. The first is the cURL resource, and the second is a string with the data to be written.
 * The data must be saved by this callback. It must return the exact number of bytes written or the transfer will be aborted with an error.
 */
const CURLOPT_WRITEFUNCTION = 20011;

/**
 * A callback accepting three parameters.
 * The first is the cURL resource,
 * the second is a stream resource provided to cURL through the option CURLOPT_INFILE,
 * and the third is the maximum amount of data to be read.
 * The callback must return a string with a length equal or smaller than the amount of data requested, typically by reading it from the passed stream resource.
 * It should return an empty string to signal EOF.
 */
const CURLOPT_READFUNCTION = 20012;

/**
 * A callback accepting two parameters. The first is the cURL resource, the second is a string with the header data to be written.
 * The header data must be written by this callback. Return the number of bytes written.
 */
const CURLOPT_HEADERFUNCTION = 20079;

/**
 * The maximum amount of HTTP redirections to follow. Use this option alongside CURLOPT_FOLLOWLOCATION.
 */
const CURLOPT_MAXREDIRS = 68;

/**
 * The maximum amount of persistent connections that are allowed.
 * When the limit is reached, CURLOPT_CLOSEPOLICY is used to determine which connection to close.
 */
const CURLOPT_MAXCONNECTS = 71;

/**
 * This option is deprecated, as it was never implemented in cURL and never had any effect.
 * @removed 5.6
 */
const CURLOPT_CLOSEPOLICY = 72;

/**
 * TRUE to force the use of a new connection instead of a cached one.
 */
const CURLOPT_FRESH_CONNECT = 74;

/**
 * TRUE to force the connection to explicitly close when it has finished processing, and not be pooled for reuse.
 */
const CURLOPT_FORBID_REUSE = 75;

/**
 * A filename to be used to seed the random number generator for SSL.
 */
const CURLOPT_RANDOM_FILE = 10076;

/**
 * Like CURLOPT_RANDOM_FILE, except a filename to an Entropy Gathering Daemon socket.
 */
const CURLOPT_EGDSOCKET = 10077;

/**
 * The number of seconds to wait while trying to connect. Use 0 to wait indefinitely.
 */
const CURLOPT_CONNECTTIMEOUT = 78;

/**
 * The number of milliseconds to wait while trying to connect. Use 0 to wait indefinitely.
 * If libcurl is built to use the standard system name resolver, that portion of the connect
 * will still use full-second resolution for timeouts with a minimum timeout allowed of one second.
 * @since 5.2
 */
const CURLOPT_CONNECTTIMEOUT_MS = 156;

/**
 * FALSE to stop cURL from verifying the peer's certificate.
 * Alternate certificates to verify against can be specified with the CURLOPT_CAINFO option or
 * a certificate directory can be specified with the CURLOPT_CAPATH option.
 */
const CURLOPT_SSL_VERIFYPEER = 64;

/**
 * The name of a file holding one or more certificates to verify the peer with.
 * This only makes sense when used in combination with CURLOPT_SSL_VERIFYPEER.
 */
const CURLOPT_CAINFO = 10065;

/**
 * A directory that holds multiple CA certificates. Use this option alongside CURLOPT_SSL_VERIFYPEER.
 */
const CURLOPT_CAPATH = 10097;

/**
 * The name of a file to save all internal cookies to when the handle is closed, e.g. after a call to curl_close.
 */
const CURLOPT_COOKIEJAR = 10082;

/**
 * A list of ciphers to use for SSL. For example, RC4-SHA and TLSv1 are valid cipher lists.
 */
const CURLOPT_SSL_CIPHER_LIST = 10083;

/**
 * TRUE to return the raw output when CURLOPT_RETURNTRANSFER is used.
 * @deprecated 5.1
 */
const CURLOPT_BINARYTRANSFER = 19914;

/**
 * TRUE to ignore any cURL function that causes a signal to be sent to the PHP process.
 * This is turned on by default in multi-threaded SAPIs so timeout options can still be used.
 */
const CURLOPT_NOSIGNAL = 99;

/**
 * Either CURLPROXY_HTTP (default), CURLPROXY_SOCKS4, CURLPROXY_SOCKS5, CURLPROXY_SOCKS4A or CURLPROXY_SOCKS5_HOSTNAME.
 */
const CURLOPT_PROXYTYPE = 101;

/**
 * The size of the buffer to use for each read. There is no guarantee this request will be fulfilled, however.
 */
const CURLOPT_BUFFERSIZE = 98;

/**
 * TRUE to reset the HTTP request method to GET. Since GET is the default, this is only necessary if the request method has been changed.
 */
const CURLOPT_HTTPGET = 80;

/**
 * CURL_HTTP_VERSION_NONE (default, lets CURL decide which version to use),
 * CURL_HTTP_VERSION_1_0 (forces HTTP/1.0), CURL_HTTP_VERSION_1_1 (forces HTTP/1.1), CURL_HTTP_VERSION_2_0 (attempts HTTP 2),
 * CURL_HTTP_VERSION_2 (alias of CURL_HTTP_VERSION_2_0), CURL_HTTP_VERSION_2TLS (attempts HTTP 2 over TLS (HTTPS) only) or
 * CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE (issues non-TLS HTTP requests using HTTP/2 without HTTP/1.1 Upgrade).
 */
const CURLOPT_HTTP_VERSION = 84;

/**
 * The name of a file containing a private SSL key.
 */
const CURLOPT_SSLKEY = 10087;

/**
 * The key type of the private SSL key specified in CURLOPT_SSLKEY.
 * Supported key types are "PEM" (default), "DER", and "ENG".
 */
const CURLOPT_SSLKEYTYPE = 10088;

/**
 * The secret password needed to use the private SSL key specified in CURLOPT_SSLKEY.
 * (Since this option contains a sensitive password, remember to keep the PHP script it is contained within safe)
 */
const CURLOPT_SSLKEYPASSWD = 10026;

/**
 * The identifier for the crypto engine of the private SSL key specified in CURLOPT_SSLKEY.
 */
const CURLOPT_SSLENGINE = 10089;

/**
 * The identifier for the crypto engine used for asymmetric crypto operations.
 */
const CURLOPT_SSLENGINE_DEFAULT = 90;

/**
 * The format of the certificate.
 * Supported formats are "PEM" (default), "DER", and "ENG". As of OpenSSL 0.9.3, "P12" (for PKCS#12-encoded files) is also supported.
 */
const CURLOPT_SSLCERTTYPE = 10086;

/**
 * TRUE to convert Unix newlines to CRLF newlines on transfers.
 */
const CURLOPT_CRLF = 27;

/**
 * The contents of the "Accept-Encoding: " header. This enables decoding of the response.
 * Supported encodings are "identity", "deflate", and "gzip".
 * If an empty string, "", is set, a header containing all supported encoding types is sent.
 */
const CURLOPT_ENCODING = 10102;

/**
 * The port number of the proxy to connect to. This port number can also be set in CURLOPT_PROXY.
 */
const CURLOPT_PROXYPORT = 59;

/**
 * TRUE to keep sending the username and password when following locations
 * (using CURLOPT_FOLLOWLOCATION), even when the hostname has changed.
 */
const CURLOPT_UNRESTRICTED_AUTH = 105;

/**
 * TRUE to use EPRT (and LPRT) when doing active FTP downloads. Use FALSE to disable EPRT and LPRT and use PORT only.
 */
const CURLOPT_FTP_USE_EPRT = 106;

/**
 * TRUE to disable TCP's Nagle algorithm, which tries to minimize the number of small packets on the network.
 * @since 5.2
 */
const CURLOPT_TCP_NODELAY = 121;

/**
 * An array of HTTP 200 responses that will be treated as valid responses and not as errors.
 */
const CURLOPT_HTTP200ALIASES = 10104;

/**
 * Value for the CURLOPT_TIMECONDITION option.
 * Return the page only if it has been modified since the time specified in CURLOPT_TIMEVALUE.
 */
const CURL_TIMECOND_IFMODSINCE = 1;

/**
 * Value for the CURLOPT_TIMECONDITION option.
 * Return the page if it hasn't been modified since the time specified in CURLOPT_TIMEVALUE.
 */
const CURL_TIMECOND_IFUNMODSINCE = 2;

/**
 * Value for the CURLOPT_TIMECONDITION option.
 */
const CURL_TIMECOND_LASTMOD = 3;

/**
 * The HTTP authentication method(s) to use.
 * The options are: CURLAUTH_BASIC, CURLAUTH_DIGEST, CURLAUTH_GSSNEGOTIATE, CURLAUTH_NTLM, CURLAUTH_ANY, and CURLAUTH_ANYSAFE.
 * The bitwise | (or) operator can be used to combine more than one method.
 * If this is done, cURL will poll the server to see what methods it supports and pick the best one.
 * CURLAUTH_ANY is an alias for CURLAUTH_BASIC | CURLAUTH_DIGEST | CURLAUTH_GSSNEGOTIATE | CURLAUTH_NTLM.
 * CURLAUTH_ANYSAFE is an alias for CURLAUTH_DIGEST | CURLAUTH_GSSNEGOTIATE | CURLAUTH_NTLM.
 */
const CURLOPT_HTTPAUTH = 107;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * Allows username/password authentication.
 */
const CURLAUTH_BASIC = 1;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 */
const CURLAUTH_DIGEST = 2;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 */
const CURLAUTH_GSSNEGOTIATE = 4;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 */
const CURLAUTH_NTLM = 8;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * Is an alias for CURLAUTH_BASIC | CURLAUTH_DIGEST | CURLAUTH_GSSNEGOTIATE | CURLAUTH_NTLM.
 */
const CURLAUTH_ANY = 4294967023;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * Is an alias for CURLAUTH_DIGEST | CURLAUTH_GSSNEGOTIATE | CURLAUTH_NTLM.
 */
const CURLAUTH_ANYSAFE = 4294967022;

/**
 * The HTTP authentication method(s) to use for the proxy connection.
 * Use the same bitmasks as described in CURLOPT_HTTPAUTH.
 * For proxy authentication, only CURLAUTH_BASIC and CURLAUTH_NTLM are currently supported.
 */
const CURLOPT_PROXYAUTH = 111;

/**
 * TRUE to create missing directories when an FTP operation encounters a path that currently doesn't exist.
 */
const CURLOPT_FTP_CREATE_MISSING_DIRS = 110;

/**
 * Any data that should be associated with this cURL handle.
 * This data can subsequently be retrieved with the CURLINFO_PRIVATE option of curl_getinfo(). cURL does nothing with this data.
 * When using a cURL multi handle, this private data is typically a unique key to identify a standard cURL handle.
 * @since 5.2
 */
const CURLOPT_PRIVATE = 10103;

/**
 * The last response code
 * @since 5.5
 */
const CURLINFO_RESPONSE_CODE = 2097154;

/**
 * The CONNECT response code
 * @since 5.5
 */
const CURLINFO_HTTP_CONNECTCODE = 2097174;

/**
 * Bitmask indicating the authentication method(s) available according to the previous response
 * @since 5.5
 */
const CURLINFO_HTTPAUTH_AVAIL = 2097175;

/**
 * Bitmask indicating the proxy authentication method(s) available according to the previous response
 * @since 5.5
 */
const CURLINFO_PROXYAUTH_AVAIL = 2097176;

/**
 * Errno from a connect failure. The number is OS and system specific.
 * @since 5.5
 */
const CURLINFO_OS_ERRNO = 2097177;

/**
 * Number of connections curl had to create to achieve the previous transfer
 * @since 5.5
 */
const CURLINFO_NUM_CONNECTS = 2097178;

/**
 * OpenSSL crypto-engines supported
 * @since 5.5
 */
const CURLINFO_SSL_ENGINES = 4194331;

/**
 * All known cookies
 * @since 5.5
 */
const CURLINFO_COOKIELIST = 4194332;

/**
 * Entry path in FTP server
 * @since 5.5
 */
const CURLINFO_FTP_ENTRY_PATH = 1048606;

/**
 * Time in seconds it took from the start until the SSL/SSH connect/handshake to the remote host was completed
 * @since 5.5
 */
const CURLINFO_APPCONNECT_TIME = 3145761;

/**
 * TLS certificate chain
 * @since 5.5
 */
const CURLINFO_CERTINFO = 4194338;

/**
 * Info on unmet time conditional
 * @since 5.5
 */
const CURLINFO_CONDITION_UNMET = 2097187;

/**
 * Next RTSP client CSeq
 * @since 5.5
 */
const CURLINFO_RTSP_CLIENT_CSEQ = 2097189;

/**
 * Recently received CSeq
 * @since 5.5
 */
const CURLINFO_RTSP_CSEQ_RECV = 2097191;

/**
 * Next RTSP server CSeq
 * @since 5.5
 */
const CURLINFO_RTSP_SERVER_CSEQ = 2097190;

/**
 * RTSP session ID
 * @since 5.5
 */
const CURLINFO_RTSP_SESSION_ID = 1048612;

/**
 * Value for the CURLOPT_CLOSEPOLICY option.
 * @removed 5.6
 */
const CURLCLOSEPOLICY_LEAST_RECENTLY_USED = 2;

/**
 * Value for the CURLOPT_CLOSEPOLICY option.
 * @removed 5.6
 */
const CURLCLOSEPOLICY_LEAST_TRAFFIC = 3;

/**
 * Value for the CURLOPT_CLOSEPOLICY option.
 * @removed 5.6
 */
const CURLCLOSEPOLICY_SLOWEST = 4;

/**
 * Value for the CURLOPT_CLOSEPOLICY option.
 * @removed 5.6
 */
const CURLCLOSEPOLICY_CALLBACK = 5;

/**
 * Value for the CURLOPT_CLOSEPOLICY option.
 * @removed 5.6
 */
const CURLCLOSEPOLICY_OLDEST = 1;

/**
 * Last effective URL
 */
const CURLINFO_EFFECTIVE_URL = 1048577;

/**
 * As of PHP 5.5.0 and cURL 7.10.8, this is a legacy alias of CURLINFO_RESPONSE_CODE.
 */
const CURLINFO_HTTP_CODE = 2097154;

/**
 * Total size of all headers received
 */
const CURLINFO_HEADER_SIZE = 2097163;

/**
 * Total size of issued requests, currently only for HTTP requests
 */
const CURLINFO_REQUEST_SIZE = 2097164;

/**
 * Total transaction time in seconds for last transfer
 */
const CURLINFO_TOTAL_TIME = 3145731;

/**
 * Time in seconds until name resolving was complete
 */
const CURLINFO_NAMELOOKUP_TIME = 3145732;

/**
 * Time in seconds it took to establish the connection
 */
const CURLINFO_CONNECT_TIME = 3145733;

/**
 * Time in seconds from start until just before file transfer begins
 */
const CURLINFO_PRETRANSFER_TIME = 3145734;

/**
 * Total number of bytes uploaded
 */
const CURLINFO_SIZE_UPLOAD = 3145735;

/**
 * Total number of bytes downloaded
 */
const CURLINFO_SIZE_DOWNLOAD = 3145736;

/**
 * Average download speed
 */
const CURLINFO_SPEED_DOWNLOAD = 3145737;

/**
 * Average upload speed
 */
const CURLINFO_SPEED_UPLOAD = 3145738;

/**
 * Remote time of the retrieved document, with the CURLOPT_FILETIME enabled;
 * if -1 is returned the time of the document is unknown
 */
const CURLINFO_FILETIME = 2097166;

/**
 * Result of SSL certification verification requested by setting CURLOPT_SSL_VERIFYPEER
 */
const CURLINFO_SSL_VERIFYRESULT = 2097165;

/**
 * Content length of download, read from Content-Length: field
 */
const CURLINFO_CONTENT_LENGTH_DOWNLOAD = 3145743;

/**
 * Specified size of upload
 */
const CURLINFO_CONTENT_LENGTH_UPLOAD = 3145744;

/**
 * Time in seconds until the first byte is about to be transferred
 */
const CURLINFO_STARTTRANSFER_TIME = 3145745;

/**
 * Content-Type: of the requested document. NULL indicates server did not send valid Content-Type: header
 */
const CURLINFO_CONTENT_TYPE = 1048594;

/**
 * Time in seconds of all redirection steps before final transaction was started,
 * with the CURLOPT_FOLLOWLOCATION option enabled
 */
const CURLINFO_REDIRECT_TIME = 3145747;

/**
 * Number of redirects, with the CURLOPT_FOLLOWLOCATION option enabled
 */
const CURLINFO_REDIRECT_COUNT = 2097172;

/**
 * TRUE to track the handle's request string
 * @since 5.1
 */
const CURLINFO_HEADER_OUT = 2;

/**
 * Private data associated with this cURL handle, previously set with the CURLOPT_PRIVATE option of curl_getinfo()
 * @since 5.2
 */
const CURLINFO_PRIVATE = 1048597;

/**
 * @since 8.3
 */
const CURLINFO_CAPATH = 1048638;

/**
 * @since 8.3
 */
const CURLINFO_CAINFO = 1048637;

/**
 * Supports IPv6
 */
const CURL_VERSION_IPV6 = 1;

/**
 * Supports Kerberos V4 (when using FTP)
 */
const CURL_VERSION_KERBEROS4 = 2;

/**
 * Supports SSL (HTTPS/FTPS)
 */
const CURL_VERSION_SSL = 4;

/**
 * Supports HTTP deflate using libz
 */
const CURL_VERSION_LIBZ = 8;

/**
 * Will be the most recent age value for the libcurl.
 */
const CURLVERSION_NOW = 10;

/**
 * All fine. Proceed as usual.
 */
const CURLE_OK = 0;

/**
 * @since 8.3
 */
const CURLKHMATCH_OK = 0;

/**
 * @since 8.3
 */
const CURLKHMATCH_MISMATCH = 1;

/**
 * @since 8.3
 */
const CURLKHMATCH_MISSING = 2;

/**
 * @since 8.3
 */
const CURLKHMATCH_LAST = 3;

/**
 * @since 8.3
 */
const CURLOPT_MIME_OPTIONS = 315;

/**
 * @since 8.3
 */
const CURLMIMEOPT_FORMESCAPE = 1;

/**
 * The URL you passed to libcurl used a protocol that this libcurl does not support.
 * The support might be a compile-time option that you didn't use,
 * it can be a misspelled protocol string or just a protocol libcurl has no code for.
 */
const CURLE_UNSUPPORTED_PROTOCOL = 1;

/**
 * Very early initialization code failed.
 * This is likely to be an internal error or problem,
 * or a resource problem where something fundamental couldn't get done at init time.
 */
const CURLE_FAILED_INIT = 2;

/**
 * The URL was not properly formatted.
 */
const CURLE_URL_MALFORMAT = 3;

/**
 * A requested feature, protocol or option was not found built-in in this libcurl due to a build-time decision.
 */
const CURLE_URL_MALFORMAT_USER = 4;

/**
 * Couldn't resolve proxy. The given proxy host could not be resolved.
 */
const CURLE_COULDNT_RESOLVE_PROXY = 5;

/**
 * Couldn't resolve host. The given remote host was not resolved.
 */
const CURLE_COULDNT_RESOLVE_HOST = 6;

/**
 * Failed to connect to host or proxy.
 */
const CURLE_COULDNT_CONNECT = 7;

/**
 * The server sent data libcurl couldn't parse.
 * This error code was known as as CURLE_FTP_WEIRD_SERVER_REPLY before 7.51.0.
 */
const CURLE_FTP_WEIRD_SERVER_REPLY = 8;

/**
 * We were denied access to the resource given in the URL.
 * For FTP, this occurs while trying to change to the remote directory.
 */
const CURLE_FTP_ACCESS_DENIED = 9;

/**
 * While waiting for the server to connect back when an active FTP session is used,
 * an error code was sent over the control connection or similar.
 */
const CURLE_FTP_USER_PASSWORD_INCORRECT = 10;

/**
 * After having sent the FTP password to the server, libcurl expects a proper reply.
 * This error code indicates that an unexpected code was returned.
 */
const CURLE_FTP_WEIRD_PASS_REPLY = 11;

/**
 * During an active FTP session while waiting for the server to connect,
 * the CURLOPT_ACCEPTTIMEOUT_MS (or the internal default) timeout expired.
 */
const CURLE_FTP_WEIRD_USER_REPLY = 12;

/**
 * Libcurl failed to get a sensible result back from the server as a response to either a PASV or a EPSV command.
 * The server is flawed.
 */
const CURLE_FTP_WEIRD_PASV_REPLY = 13;

/**
 * FTP servers return a 227-line as a response to a PASV command.
 * If libcurl fails to parse that line, this return code is passed back.
 */
const CURLE_FTP_WEIRD_227_FORMAT = 14;

/**
 * An internal failure to lookup the host used for the new connection.
 */
const CURLE_FTP_CANT_GET_HOST = 15;

/**
 * A problem was detected in the HTTP2 framing layer.
 * This is somewhat generic and can be one out of several problems, see the error buffer for details.
 */
const CURLE_FTP_CANT_RECONNECT = 16;

/**
 * Received an error when trying to set the transfer mode to binary or ASCII.
 */
const CURLE_FTP_COULDNT_SET_BINARY = 17;

/**
 * A file transfer was shorter or larger than expected.
 * This happens when the server first reports an expected transfer size, and then delivers data
 * that doesn't match the previously given size.
 */
const CURLE_PARTIAL_FILE = 18;

/**
 * This was either a weird reply to a 'RETR' command or a zero byte transfer complete.
 */
const CURLE_FTP_COULDNT_RETR_FILE = 19;

/**
 * After a completed file transfer, the FTP server did not respond a proper
 */
const CURLE_FTP_WRITE_ERROR = 20;

/**
 * When sending custom "QUOTE" commands to the remote server,
 * one of the commands returned an error code that was 400 or higher (for FTP) or otherwise indicated unsuccessful completion of the command.
 */
const CURLE_FTP_QUOTE_ERROR = 21;

/**
 * This is returned if CURLOPT_FAILONERROR is set TRUE and the HTTP server returns an error code that is >= 400.
 */
const CURLE_HTTP_NOT_FOUND = 22;

/**
 * An error occurred when writing received data to a local file, or an error was returned to libcurl from a write callback.
 */
const CURLE_WRITE_ERROR = 23;

const CURLE_MALFORMAT_USER = 24;

/**
 * Failed starting the upload. For FTP, the server typically denied the STOR command.
 * The error buffer usually contains the server's explanation for this.
 */
const CURLE_FTP_COULDNT_STOR_FILE = 25;

/**
 * There was a problem reading a local file or an error returned by the read callback.
 */
const CURLE_READ_ERROR = 26;

/**
 * A memory allocation request failed. This is serious badness and things are severely screwed up if this ever occurs.
 */
const CURLE_OUT_OF_MEMORY = 27;

/**
 * Operation timeout. The specified time-out period was reached according to the conditions.
 */
const CURLE_OPERATION_TIMEOUTED = 28;

/**
 * libcurl failed to set ASCII transfer type (TYPE A).
 */
const CURLE_FTP_COULDNT_SET_ASCII = 29;

/**
 * The FTP PORT command returned error.
 * This mostly happens when you haven't specified a good enough address for libcurl to use. See CURLOPT_FTPPORT.
 */
const CURLE_FTP_PORT_FAILED = 30;

/**
 * The FTP REST command returned error. This should never happen if the server is sane.
 */
const CURLE_FTP_COULDNT_USE_REST = 31;

/**
 * The FTP SIZE command returned error. SIZE is not a kosher FTP command,
 * it is an extension and not all servers support it.
 */
const CURLE_FTP_COULDNT_GET_SIZE = 32;

/**
 * The server does not support or accept range requests.
 */
const CURLE_HTTP_RANGE_ERROR = 33;

/**
 * This is an odd error that mainly occurs due to internal confusion.
 */
const CURLE_HTTP_POST_ERROR = 34;

/**
 * A problem occurred somewhere in the SSL/TLS handshake.
 * You really want the error buffer and read the message there as it pinpoints the problem slightly more.
 * Could be certificates (file formats, paths, permissions), passwords, and others.
 */
const CURLE_SSL_CONNECT_ERROR = 35;

/**
 * The download could not be resumed because the specified offset was out of the file boundary.
 */
const CURLE_FTP_BAD_DOWNLOAD_RESUME = 36;

/**
 * A file given with FILE:// couldn't be opened.
 * Most likely because the file path doesn't identify an existing file. Did you check file permissions?
 */
const CURLE_FILE_COULDNT_READ_FILE = 37;

/**
 * LDAP cannot bind. LDAP bind operation failed.
 */
const CURLE_LDAP_CANNOT_BIND = 38;

/**
 * LDAP search failed.
 */
const CURLE_LDAP_SEARCH_FAILED = 39;

/**
 * Library not found. The LDAP library was not found.
 */
const CURLE_LIBRARY_NOT_FOUND = 40;

/**
 * Function not found. A required zlib function was not found.
 */
const CURLE_FUNCTION_NOT_FOUND = 41;

/**
 * Aborted by callback. A callback returned "abort" to libcurl.
 */
const CURLE_ABORTED_BY_CALLBACK = 42;

/**
 * A function was called with a bad parameter.
 */
const CURLE_BAD_FUNCTION_ARGUMENT = 43;

/**
 * This is never returned
 */
const CURLE_BAD_CALLING_ORDER = 44;

/**
 * Interface error. A specified outgoing interface could not be used.
 * Set which interface to use for outgoing connections' source IP address with CURLOPT_INTERFACE.
 */
const CURLE_HTTP_PORT_FAILED = 45;

/**
 * This is never returned
 */
const CURLE_BAD_PASSWORD_ENTERED = 46;

/**
 * Too many redirects. When following redirects, libcurl hit the maximum amount.
 * Set your limit with CURLOPT_MAXREDIRS.
 */
const CURLE_TOO_MANY_REDIRECTS = 47;

/**
 * An option passed to libcurl is not recognized/known. Refer to the appropriate documentation.
 * This is most likely a problem in the program that uses libcurl.
 * The error buffer might contain more specific information about which exact option it concerns.
 */
const CURLE_UNKNOWN_TELNET_OPTION = 48;

/**
 * A telnet option string was Illegally formatted.
 */
const CURLE_TELNET_OPTION_SYNTAX = 49;

/**
 * Currently unused.
 */
const CURLE_OBSOLETE = 50;

/**
 * The remote server's SSL certificate or SSH md5 fingerprint was deemed not OK.
 * This error code has been unified with CURLE_SSL_CACERT since 7.62.0. Its previous value was 51.
 */
const CURLE_SSL_PEER_CERTIFICATE = 60;

/**
 * Nothing was returned from the server, and under the circumstances, getting nothing is considered an error.
 */
const CURLE_GOT_NOTHING = 52;

/**
 * The specified crypto engine wasn't found.
 */
const CURLE_SSL_ENGINE_NOTFOUND = 53;

/**
 * Failed setting the selected SSL crypto engine as default!
 */
const CURLE_SSL_ENGINE_SETFAILED = 54;

/**
 * Failed sending network data.
 */
const CURLE_SEND_ERROR = 55;

/**
 * Failure with receiving network data.
 */
const CURLE_RECV_ERROR = 56;

/**
 * The share object is currently in use.
 */
const CURLE_SHARE_IN_USE = 57;

/**
 * Problem with the local client certificate.
 */
const CURLE_SSL_CERTPROBLEM = 58;

/**
 * Couldn't use specified cipher.
 */
const CURLE_SSL_CIPHER = 59;

/**
 * The remote server's SSL certificate or SSH md5 fingerprint was deemed not OK.
 * This error code has been unified with CURLE_SSL_PEER_CERTIFICATE since 7.62.0.
 */
const CURLE_SSL_CACERT = 60;

/**
 * Unrecognized transfer encoding.
 */
const CURLE_BAD_CONTENT_ENCODING = 61;

/**
 * Invalid LDAP URL.
 */
const CURLE_LDAP_INVALID_URL = 62;

/**
 * Maximum file size exceeded.
 */
const CURLE_FILESIZE_EXCEEDED = 63;

/**
 * Requested FTP SSL level failed.
 */
const CURLE_FTP_SSL_FAILED = 64;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 */
const CURLPROXY_HTTP = 0;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 */
const CURLPROXY_SOCKS4 = 4;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 */
const CURLPROXY_SOCKS5 = 5;

/**
 * Value for the CURLOPT_NETRC option.
 * The use of the ~/.netrc file is optional, and information in the URL is to be preferred.
 * The file will be scanned for the host and user name (to find the password only) or for the host only,
 * to find the first user name and password after that machine, which ever information is not specified.
 */
const CURL_NETRC_OPTIONAL = 1;

/**
 * Value for the CURLOPT_NETRC option.
 * The library will ignore the ~/.netrc file. This is the default.
 */
const CURL_NETRC_IGNORED = 0;

/**
 * Value for the CURLOPT_NETRC option.
 * The use of the ~/.netrc file is required, and information in the URL is to be ignored.
 * The file will be scanned for the host and user name (to find the password only) or for the host only,
 * to find the first user name and password after that machine, which ever information is not specified.
 */
const CURL_NETRC_REQUIRED = 2;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Let's CURL decide which version to use.
 */
const CURL_HTTP_VERSION_NONE = 0;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Forces HTTP/1.0.
 */
const CURL_HTTP_VERSION_1_0 = 1;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Forces HTTP/1.1.
 */
const CURL_HTTP_VERSION_1_1 = 2;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Attempts HTTP 2.
 */
const CURL_HTTP_VERSION_2_0 = 3;

/**
 * This is not really an error. It means you should call curl_multi_exec() again without doing select() or similar in between.
 * Before version 7.20.0 this could be returned by curl_multi_exec(), but in later versions this return code is never used.
 */
const CURLM_CALL_MULTI_PERFORM = -1;

/**
 * Things are fine.
 */
const CURLM_OK = 0;

/**
 * The passed-in handle is not a valid CURLM handle.
 */
const CURLM_BAD_HANDLE = 1;

/**
 * An easy handle was not good/valid. It could mean that it isn't an easy handle at all,
 * or possibly that the handle already is in use by this or another multi handle.
 */
const CURLM_BAD_EASY_HANDLE = 2;

/**
 * Out of memory error.
 */
const CURLM_OUT_OF_MEMORY = 3;

/**
 * libcurl' internal error.
 */
const CURLM_INTERNAL_ERROR = 4;

/**
 * The message identifies a transfer that is done, and then result contains the return code for the easy handle that just completed.
 * Other return values are currently not available.
 */
const CURLMSG_DONE = 1;

/**
 * The FTP authentication method (when is activated):
 * CURLFTPAUTH_SSL (try SSL first), CURLFTPAUTH_TLS (try TLS first), or CURLFTPAUTH_DEFAULT (let cURL decide).
 */
const CURLOPT_FTPSSLAUTH = 129;

/**
 * Value for the CURLOPT_FTPSSLAUTH option.
 * Let cURL decide FTP authentication method.
 */
const CURLFTPAUTH_DEFAULT = 0;

/**
 * Value for the CURLOPT_FTPSSLAUTH option.
 * Try SSL first as FTP authentication method.
 */
const CURLFTPAUTH_SSL = 1;

/**
 * Value for the CURLOPT_FTPSSLAUTH option.
 * Try TLS first as FTP authentication method.
 */
const CURLFTPAUTH_TLS = 2;

/**
 * @deprecated use CURLOPT_USE_SSL instead.
 */
const CURLOPT_FTP_SSL = 119;

/**
 * Value for the CURLOPT_FTP_SSL option.
 * Don't attempt to use SSL.
 */
const CURLFTPSSL_NONE = 0;

/**
 * Value for the CURLOPT_FTP_SSL option.
 * Try using SSL, proceed as normal otherwise.
 */
const CURLFTPSSL_TRY = 1;

/**
 * Value for the CURLOPT_FTP_SSL option.
 * Require SSL for the control connection or fail.
 */
const CURLFTPSSL_CONTROL = 2;

/**
 * Value for the CURLOPT_FTP_SSL option.
 * Require SSL for all communication or fail.
 */
const CURLFTPSSL_ALL = 3;

/**
 * Tell curl which method to use to reach a file on a FTP(S) server.
 * Possible values are CURLFTPMETHOD_MULTICWD, CURLFTPMETHOD_NOCWD and CURLFTPMETHOD_SINGLECWD.
 * @since 5.3
 */
const CURLOPT_FTP_FILEMETHOD = 138;

/**
 * Ignore the IP address in the PASV response
 */
const CURLOPT_FTP_SKIP_PASV_IP = 137;

/**
 * TRUE to disable support for the @ prefix for uploading files in CURLOPT_POSTFIELDS,
 * which means that values starting with @ can be safely passed as fields.
 * @since 5.5
 * @deprecated 7.0 Use CURLFile for uploads instead.
 */
const CURLOPT_SAFE_UPLOAD = -1;

/**
 * Value for the CURLOPT_FTP_FILEMETHOD option.
 * libcurl does a single CWD operation for each path part in the given URL.
 * For deep hierarchies this means many commands. This is how RFC 1738 says it should be done. This is the default but the slowest behavior.
 */
const CURLFTPMETHOD_MULTICWD = 1;

/**
 * Value for the CURLOPT_FTP_FILEMETHOD option.
 * libcurl does no CWD at all.
 * libcurl will do SIZE, RETR, STOR etc and give a full path to the server for all these commands. This is the fastest behavior.
 */
const CURLFTPMETHOD_NOCWD = 2;

/**
 * Value for the CURLOPT_FTP_FILEMETHOD option.
 * libcurl does one CWD with the full target directory and then operates on the file "normally" (like in the multicwd case).
 * This is somewhat more standards compliant than 'nocwd' but without the full penalty of 'multicwd'.
 */
const CURLFTPMETHOD_SINGLECWD = 3;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_HTTP = 1;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_HTTPS = 2;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_FTP = 4;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_FTPS = 8;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_SCP = 16;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_SFTP = 32;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_TELNET = 64;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_LDAP = 128;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_LDAPS = 256;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_DICT = 512;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_FILE = 1024;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_TFTP = 2048;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_ALL = 4294967295;

/**
 * As of cURL 7.43.0, the value is a bitmask.
 * Pass 1 to enable or 0 to disable.
 * Enabling pipelining on a multi handle will make it attempt to perform HTTP Pipelining as far as possible for transfers
 * using this handle. This means that if you add a second request that can use an already existing connection,
 * the second request will be "piped" on the same connection.
 * Pass 2 to try to multiplex the new transfer over an existing HTTP/2 connection if possible.
 * Pass 3 instructs cURL to ask for pipelining and multiplexing independently of each other.
 * As of cURL 7.62.0, setting the pipelining bit has no effect.
 * Instead of integer literals, you can also use the CURLPIPE_* constants if available.
 * @since 5.5
 */
const CURLMOPT_PIPELINING = 3;

/**
 * Pass a number that will be used as the maximum amount of simultaneously open connections that libcurl may cache.
 * By default the size will be enlarged to fit four times the number of handles added via curl_multi_add_handle().
 * When the cache is full, curl closes the oldest one in the cache to prevent the number of open connections from increasing.
 * @since 5.5
 */
const CURLMOPT_MAXCONNECTS = 6;

/**
 * Specifies a type of data that should be shared.
 */
const CURLSHOPT_SHARE = 1;

/**
 * Specifies a type of data that will be no longer shared.
 */
const CURLSHOPT_UNSHARE = 2;

/**
 * Value for the CURLSHOPT_SHARE option.
 * Shares cookie data.
 */
const CURL_LOCK_DATA_COOKIE = 2;

/**
 * Value for the CURLSHOPT_SHARE option.
 * Shares DNS cache. Note that when you use cURL multi handles,
 * all handles added to the same multi handle will share DNS cache by default.
 */
const CURL_LOCK_DATA_DNS = 3;

/**
 * Value for the CURLSHOPT_SHARE option.
 * Shares SSL session IDs, reducing the time spent on the SSL handshake when reconnecting to the same server.
 * Note that SSL session IDs are reused within the same handle by default.
 */
const CURL_LOCK_DATA_SSL_SESSION = 4;

/**
 * The password required to use the CURLOPT_SSLKEY or CURLOPT_SSH_PRIVATE_KEYFILE private key.
 */
const CURLOPT_KEYPASSWD = 10026;

/**
 * Value for the CURLOPT_FTP_CREATE_MISSING_DIRS option.
 * libcurl will attempt to create any remote directory that it fails to "move" into.
 * @since 7.0
 */
const CURLFTP_CREATE_DIR = 1;

/**
 * Value for the CURLOPT_FTP_CREATE_MISSING_DIRS option.
 * libcurl will not attempt to create any remote directory that it fails to "move" into.
 * @since 7.0
 */
const CURLFTP_CREATE_DIR_NONE = 0;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * NTLM delegating to winbind helper.
 * Authentication is performed by a separate binary application that is executed when needed.
 * The name of the application is specified at compile time but is typically /usr/bin/ntlm_auth.
 * @since 7.0
 */
const CURLAUTH_NTLM_WB = 32;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Alias of CURL_HTTP_VERSION_2_0
 * Attempts HTTP 2
 * @since 7.0
 */
const CURL_HTTP_VERSION_2 = 3;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Attempts HTTP 2 over TLS (HTTPS) only
 * @since 7.0
 */
const CURL_HTTP_VERSION_2TLS = 4;

/**
 * Value for the CURLOPT_HTTP_VERSION option.
 * Issues non-TLS HTTP requests using HTTP/2 without HTTP/1.1 Upgrade
 * @since 7.0
 */
const CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE = 5;

/**
 * TRUE to enable sending the initial response in the first packet.
 * @since 7.0
 */
const CURLOPT_SASL_IR = 218;

/**
 * Set the name of the network interface that the DNS resolver should bind to. This must be an interface name (not an address).
 * @since 7.0
 */
const CURLOPT_DNS_INTERFACE = 10221;

/**
 * Set the local IPv4 address that the resolver should bind to. The argument should contain a single numerical IPv4 address as a string.
 * @since 7.0
 */
const CURLOPT_DNS_LOCAL_IP4 = 10222;

/**
 * Set the local IPv6 address that the resolver should bind to. The argument should contain a single numerical IPv6 address as a string.
 * @since 7.0
 */
const CURLOPT_DNS_LOCAL_IP6 = 10223;

/**
 * Specifies the OAuth 2.0 access token.
 * @since 7.0
 */
const CURLOPT_XOAUTH2_BEARER = 10220;

/**
 * Can be used to set protocol specific login options, such as the preferred authentication mechanism via "AUTH=NTLM" or "AUTH=*",
 * and should be used in conjunction with the CURLOPT_USERNAME option.
 * @since 7.0
 */
const CURLOPT_LOGIN_OPTIONS = 10224;

/**
 * The timeout for Expect: 100-continue responses in milliseconds. Defaults to 1000 milliseconds.
 * @since 7.0
 */
const CURLOPT_EXPECT_100_TIMEOUT_MS = 227;

/**
 * FALSE to disable ALPN in the SSL handshake (if the SSL backend libcurl is built to use supports it),
 * which can be used to negotiate http2.
 * @since 7.0
 */
const CURLOPT_SSL_ENABLE_ALPN = 226;

/**
 * FALSE to disable NPN in the SSL handshake (if the SSL backend libcurl is built to use supports it),
 * which can be used to negotiate http2.
 * @since 7.0
 */
const CURLOPT_SSL_ENABLE_NPN = 225;

/**
 * Set the pinned public key. The string can be the file name of your pinned public key. The file format expected is "PEM" or "DER".
 * The string can also be any number of base64 encoded sha256 hashes preceded by "sha256//" and separated by ";".
 * @since 7.0
 */
const CURLOPT_PINNEDPUBLICKEY = 10230;

/**
 * Enables the use of Unix domain sockets as connection endpoint and sets the path to the given string.
 * @since 7.0
 */
const CURLOPT_UNIX_SOCKET_PATH = 10231;

/**
 * TRUE to verify the certificate's status.
 * @since 7.0
 */
const CURLOPT_SSL_VERIFYSTATUS = 232;

/**
 * TRUE to not handle dot dot sequences.
 * @since 7.0
 */
const CURLOPT_PATH_AS_IS = 234;

/**
 * TRUE to enable TLS false start.
 * @since 7.0
 */
const CURLOPT_SSL_FALSESTART = 233;

/**
 * TRUE to wait for pipelining/multiplexing.
 * @since 7.0
 */
const CURLOPT_PIPEWAIT = 237;

/**
 * The proxy authentication service name.
 * @since 7.0
 */
const CURLOPT_PROXY_SERVICE_NAME = 10235;

/**
 * The authentication service name.
 * @since 7.0
 */
const CURLOPT_SERVICE_NAME = 10236;

/**
 * @since 8.3
 */
const CURLOPT_SSH_HOSTKEYFUNCTION = 20316;

/**
 * @since 8.3
 */
const CURLOPT_PROTOCOLS_STR = 10318;

/**
 * @since 8.3
 */
const CURLOPT_REDIR_PROTOCOLS_STR = 10319;

/**
 * @since 8.3
 */
const CURLOPT_WS_OPTIONS = 320;

/**
 * @since 8.3
 */
const CURLWS_RAW_MODE = 1;

/**
 * @since 8.3
 */
const CURLOPT_CA_CACHE_TIMEOUT = 321;

/**
 * @since 8.3
 */
const CURLOPT_QUICK_EXIT = 322;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 * libcurl attempts to connect to ssh-agent or pageant and let the agent attempt the authentication.
 * @since 7.0
 */
const CURLSSH_AUTH_AGENT = 16;

/**
 * Value for the CURLMOPT_PIPELINING option.
 * Default, which means doing no attempts at pipelining or multiplexing.
 * @since 7.0
 */
const CURLPIPE_NOTHING = 0;

/**
 * Value for the CURLMOPT_PIPELINING option.
 * If this bit is set, libcurl will try to pipeline HTTP/1.1 requests on connections that are already established and in use to hosts.
 * @deprecated 7.4
 * @since 7.0
 */
const CURLPIPE_HTTP1 = 1;

/**
 * Value for the CURLMOPT_PIPELINING option.
 * If this bit is set, libcurl will try to multiplex the new transfer over an existing connection if possible. This requires HTTP/2.
 * @since 7.0
 */
const CURLPIPE_MULTIPLEX = 2;

/**
 * Value for the CURLOPT_HEADEROPT option.
 * Makes CURLOPT_HTTPHEADER headers only get sent to a server and not to a proxy.
 * Proxy headers must be set with CURLOPT_PROXYHEADER to get used.
 * @since 7.0
 */
const CURLHEADER_SEPARATE = 1;

/**
 * Value for the CURLOPT_HEADEROPT option.
 * The headers specified in CURLOPT_HTTPHEADER will be used in requests both to servers and proxies.
 * With this option enabled, CURLOPT_PROXYHEADER will not have any effect.
 * @since 7.0
 */
const CURLHEADER_UNIFIED = 0;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 * @since 7.0
 */
const CURLPROTO_SMB = 67108864;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 * @since 7.0
 */
const CURLPROTO_SMBS = 134217728;

/**
 * How to deal with headers.
 * One of the following constants:
 * CURLHEADER_UNIFIED: the headers specified in CURLOPT_HTTPHEADER will be used in requests both to servers and proxies.
 * With this option enabled, CURLOPT_PROXYHEADER will not have any effect.
 * CURLHEADER_SEPARATE: makes CURLOPT_HTTPHEADER headers only get sent to a server and not to a proxy.
 * Proxy headers must be set with CURLOPT_PROXYHEADER to get used.
 * Note that if a non-CONNECT request is sent to a proxy, libcurl will send both server headers and proxy headers.
 * When doing CONNECT, libcurl will send CURLOPT_PROXYHEADER headers only to the proxy and then CURLOPT_HTTPHEADER headers only to the server.
 * Defaults to CURLHEADER_SEPARATE as ...
 * @since 7.0
 */
const CURLOPT_HEADEROPT = 229;

/**
 * An array of custom HTTP headers to pass to proxies.
 * @since 7.0
 */
const CURLOPT_PROXYHEADER = 10228;

/**
 * Value for the CURLOPT_POSTREDIR option.
 * @since 7.0
 */
const CURL_REDIR_POST_301 = 1;

/**
 * Value for the CURLOPT_POSTREDIR option.
 * @since 7.0
 */
const CURL_REDIR_POST_302 = 2;

/**
 * Value for the CURLOPT_POSTREDIR option.
 * @since 7.0
 */
const CURL_REDIR_POST_303 = 4;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 * @since 7.0
 */
const CURLPROXY_HTTP_1_0 = 1;

/**
 * Value for the CURLOPT_POSTREDIR option.
 * @since 7.0
 */
const CURL_REDIR_POST_ALL = 7;

/**
 * Pass a number that specifies the chunk length threshold for pipelining in bytes.
 * @since 7.0
 */
const CURLMOPT_CHUNK_LENGTH_PENALTY_SIZE = 30010;

/**
 * Pass a number that specifies the size threshold for pipelining penalty in bytes.
 * @since 7.0
 */
const CURLMOPT_CONTENT_LENGTH_PENALTY_SIZE = 30009;

/**
 * Pass a number that specifies the maximum number of connections to a single host.
 * @since 7.0
 */
const CURLMOPT_MAX_HOST_CONNECTIONS = 7;

/**
 * Pass a number that specifies the maximum number of requests in a pipeline.
 * @since 7.0
 */
const CURLMOPT_MAX_PIPELINE_LENGTH = 8;

/**
 * Pass a number that specifies the maximum number of simultaneously open connections.
 * @since 7.0
 */
const CURLMOPT_MAX_TOTAL_CONNECTIONS = 13;

/**
 * Value for the CURLOPT_FTP_CREATE_MISSING_DIRS option.
 * libcurl will not attempt to create any remote directory that it fails to "move" into.
 * Tells libcurl to retry the CWD command again if the subsequent MKD command fails.
 * @since 7.0
 */
const CURLFTP_CREATE_DIR_RETRY = 2;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * HTTP Negotiate (SPNEGO) authentication
 * @since 7.0
 */
const CURLAUTH_NEGOTIATE = 4;

/**
 * Pass a callable that will be registered to handle server pushes and should have the following signature:
 * parent_ch
 * The parent cURL handle (the request the client made).
 * pushed_ch
 * A new cURL handle for the pushed request.
 * headers
 * The push promise headers.
 * The push function is supposed to return either CURL_PUSH_OK if it can handle the push,
 * or CURL_PUSH_DENY to reject it.
 * @since 7.1
 */
const CURLMOPT_PUSHFUNCTION = 20014;

/**
 * Returned value from the push function - can handle the push.
 * @since 7.1
 */
const CURL_PUSH_OK = 0;

/**
 * Returned value from the push function - can't handle the push.
 * @since 7.1
 */
const CURL_PUSH_DENY = 1;

/**
 * The default buffer size for CURLOPT_BUFFERSIZE
 * @since 7.0
 */
const CURL_MAX_READ_SIZE = 10485760;

/**
 * Enables the use of an abstract Unix domain socket instead of establishing a TCP connection to a host and sets the path to the given string.
 * This option shares the same semantics as CURLOPT_UNIX_SOCKET_PATH.
 * These two options share the same storage and therefore only one of them can be set per handle.
 * @since 7.3
 */
const CURLOPT_ABSTRACT_UNIX_SOCKET = 10264;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_DEFAULT = 65536;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_NONE = 0;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_TLSv1_0 = 262144;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_TLSv1_1 = 327680;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_TLSv1_2 = 393216;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_MAX_TLSv1_3 = 458752;

/**
 * TRUE to suppress proxy CONNECT response headers from the user callback functions
 * CURLOPT_HEADERFUNCTION and CURLOPT_WRITEFUNCTION,
 * when CURLOPT_HTTPPROXYTUNNEL is used and a CONNECT request is made.
 * @since 7.3
 */
const CURLOPT_SUPPRESS_CONNECT_HEADERS = 265;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * Allows GSS-API authentication.
 * @since 7.3
 */
const CURLAUTH_GSSAPI = 4;

/**
 * The content-length of the download. This is the value read from the Content-Type: field. -1 if the size isn't known
 * @since 7.3
 */
const CURLINFO_CONTENT_LENGTH_DOWNLOAD_T = 6291471;

/**
 * The specified size of the upload. -1 if the size isn't known
 * @since 7.3
 */
const CURLINFO_CONTENT_LENGTH_UPLOAD_T = 6291472;

/**
 * Total number of bytes that were downloaded.
 * The number is only for the latest transfer and will be reset again for each new transfer
 * @since 7.3
 */
const CURLINFO_SIZE_DOWNLOAD_T = 6291464;

/**
 * Total number of bytes that were uploaded
 * @since 7.3
 */
const CURLINFO_SIZE_UPLOAD_T = 6291463;

/**
 * The average download speed in bytes/second that curl measured for the complete download
 * @since 7.3
 */
const CURLINFO_SPEED_DOWNLOAD_T = 6291465;

/**
 * The average upload speed in bytes/second that curl measured for the complete upload
 * @since 7.3
 */
const CURLINFO_SPEED_UPLOAD_T = 6291466;

/**
 * Specify an alternative target for this request
 * @since 7.3
 */
const CURLOPT_REQUEST_TARGET = 10266;

/**
 * The SOCKS5 authentication method(s) to use. The options are: CURLAUTH_BASIC, CURLAUTH_GSSAPI, CURLAUTH_NONE.
 * The bitwise | (or) operator can be used to combine more than one method. If this is done,
 * cURL will poll the server to see what methods it supports and pick the best one.
 * CURLAUTH_BASIC allows username/password authentication.
 * CURLAUTH_GSSAPI allows GSS-API authentication.
 * CURLAUTH_NONE allows no authentication.
 * Defaults to CURLAUTH_BASIC|CURLAUTH_GSSAPI.
 * Set the actual username and password with the CURLOPT_PROXYUSERPWD option.
 * @since 7.3
 */
const CURLOPT_SOCKS5_AUTH = 267;

/**
 * TRUE to enable built-in SSH compression. This is a request, not an order; the server may or may not do it.
 * @since 7.3
 */
const CURLOPT_SSH_COMPRESSION = 268;

/**
 * libcurl was build with multiple ssh backends.
 * @since 7.3
 */
const CURL_VERSION_MULTI_SSL = 4194304;

/**
 * Supports HTTP Brotli content encoding using libbrotlidec
 * @since 7.3
 */
const CURL_VERSION_BROTLI = 8388608;

/**
 * Value for the CURLSHOPT_SHARE option.
 * Put the connection cache in the share object and make all easy handles using this share object share the connection cache.
 * Using this, you can for example do multi-threaded libcurl use with one handle in each thread, and yet
 * have a shared pool of unused connections and this way get way better connection re-use
 * than if you use one separate pool in each thread.
 * Connections that are used for HTTP/1.1 Pipelining or HTTP/2 multiplexing only get additional transfers
 * added to them if the existing connection is held by the same multi or easy handle.
 * libcurl does not support doing HTTP/2 streams in different threads using a shared connection.
 * @since 7.3
 */
const CURL_LOCK_DATA_CONNECT = 5;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 * @since 7.3
 */
const CURLSSH_AUTH_GSSAPI = 32;

/**
 * Remote time of the retrieved document (as Unix timestamp),
 * an alternative to CURLINFO_FILETIME to allow systems with 32 bit long variables to extract dates
 * outside of the 32bit timestamp range
 * @since 7.3
 */
const CURLINFO_FILETIME_T = 6291470;

/**
 * Head start for ipv6 for the happy eyeballs algorithm.
 * Happy eyeballs attempts to connect to both IPv4 and IPv6 addresses for dual-stack hosts,
 * preferring IPv6 first for timeout milliseconds.
 * Defaults to CURL_HET_DEFAULT, which is currently 200 milliseconds.
 * @since 7.3
 */
const CURLOPT_HAPPY_EYEBALLS_TIMEOUT_MS = 271;

/**
 * The time in seconds since January 1st, 1970.
 * The time will be used by CURLOPT_TIMECONDITION. Defaults to zero.
 * The difference between this option and CURLOPT_TIMEVALUE is the type of the argument.
 * On systems where 'long' is only 32 bit wide, this option has to be used to set dates beyond the year 2038.
 * @since 7.3
 */
const CURLOPT_TIMEVALUE_LARGE = 30270;

/**
 * TRUE to shuffle the order of all returned addresses so that they will be used in a random order,
 * when a name is resolved and more than one IP address is returned.
 * This may cause IPv4 to be used before IPv6 or vice versa.
 * @since 7.3
 */
const CURLOPT_DNS_SHUFFLE_ADDRESSES = 275;

/**
 * TRUE to send an HAProxy PROXY protocol v1 header at the start of the connection.
 * The default action is not to send this header.
 * @since 7.3
 */
const CURLOPT_HAPROXYPROTOCOL = 274;

/**
 * Value for the CURLSHOPT_SHARE option.
 * The Public Suffix List stored in the share object is made available to all easy handle bound to the later.
 * Since the Public Suffix List is periodically refreshed, this avoids updates in too many different contexts.
 * @since 7.3
 */
const CURL_LOCK_DATA_PSL = 6;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * HTTP Bearer token authentication, used primarily in OAuth 2.0 protocol.
 * @since 7.3
 */
const CURLAUTH_BEARER = 64;

/**
 * Time, in microseconds, it took from the start until the SSL/SSH connect/handshake to the remote host was completed
 * @since 7.3
 */
const CURLINFO_APPCONNECT_TIME_T = 6291512;

/**
 * Total time taken, in microseconds, from the start until the connection to the remote host (or proxy) was completed
 * @since 7.3
 */
const CURLINFO_CONNECT_TIME_T = 6291508;

/**
 * Time in microseconds from the start until the name resolving was completed
 * @since 7.3
 */
const CURLINFO_NAMELOOKUP_TIME_T = 6291507;

/**
 * Time taken from the start until the file transfer is just about to begin, in microseconds
 * @since 7.3
 */
const CURLINFO_PRETRANSFER_TIME_T = 6291509;

/**
 * Total time, in microseconds,
 * it took for all redirection steps include name lookup, connect, pretransfer and transfer before final transaction was started
 * @since 7.3
 */
const CURLINFO_REDIRECT_TIME_T = 6291511;

/**
 * Time, in microseconds, it took from the start until the first byte is received
 * @since 7.3
 */
const CURLINFO_STARTTRANSFER_TIME_T = 6291510;

/**
 * Total time in microseconds for the previous transfer, including name resolving, TCP connect etc.
 * @since 7.3
 */
const CURLINFO_TOTAL_TIME_T = 6291506;

/**
 * TRUE to not allow URLs that include a username. Usernames are allowed by default (0).
 * @since 7.3
 */
const CURLOPT_DISALLOW_USERNAME_IN_URL = 278;

/**
 * The list of cipher suites to use for the TLS 1.3 connection to a proxy.
 * The list must be syntactically correct, it consists of one or more cipher suite strings separated by colons.
 * This option is currently used only when curl is built to use OpenSSL 1.1.1 or later.
 * If you are using a different SSL backend you can try setting TLS 1.3 cipher suites by using the CURLOPT_PROXY_SSL_CIPHER_LIST option.
 * @since 7.3
 */
const CURLOPT_PROXY_TLS13_CIPHERS = 10277;

/**
 * The list of cipher suites to use for the TLS 1.3 connection.
 * The list must be syntactically correct, it consists of one or more cipher suite strings separated by colons.
 * This option is currently used only when curl is built to use OpenSSL 1.1.1 or later.
 * If you are using a different SSL backend you can try setting TLS 1.3 cipher suites by using the CURLOPT_SSL_CIPHER_LIST option.
 * @since 7.3
 */
const CURLOPT_TLS13_CIPHERS = 10276;

/**
 * Time allowed to wait for FTP response.
 * @since 5.5
 */
const CURLOPT_FTP_RESPONSE_TIMEOUT = 112;

/**
 * Provide a custom address for a specific host and port pair.
 * An array of hostname, port, and IP address strings, each element separated by a colon.
 * In the format: array("example.com:80:127.0.0.1")
 * @since 5.5
 */
const CURLOPT_RESOLVE = 10203;

/**
 * Enable appending to the remote file
 * @since 5.5
 */
const CURLOPT_APPEND = 50;

/**
 * Ask for names only in a directory listing
 * @since 5.5
 */
const CURLOPT_DIRLISTONLY = 48;

/**
 * Permissions for remotely created directories
 * Pass a long as a parameter, containing the value of the permissions that will be assigned to newly created directories on the remote server.
 * The default value is 0755, but any valid value can be used.
 * The only protocols that can use this are sftp://, scp://, and file://.
 * @since 5.5
 */
const CURLOPT_NEW_DIRECTORY_PERMS = 160;

/**
 * Permissions for remotely created files.
 * Pass a long as a parameter, containing the value of the permissions that will be assigned to newly created files on the remote server.
 * The default value is 0644, but any valid value can be used.
 * The only protocols that can use this are sftp://, scp://, and file://.
 * @since 5.5
 */
const CURLOPT_NEW_FILE_PERMS = 159;

/**
 * TRUE to scan the ~/.netrc file to find a username and password for the remote site that a connection is being established with.
 * @since 5.5
 */
const CURLOPT_NETRC_FILE = 10118;

/**
 * Commands to run before an FTP transfer
 * @since 5.5
 */
const CURLOPT_PREQUOTE = 10093;

/**
 * Set FTP kerberos security level
 * @since 5.5
 */
const CURLOPT_KRBLEVEL = 10063;

/**
 * Maximum file size allowed to download (in bytes)
 * @since 5.5
 */
const CURLOPT_MAXFILESIZE = 114;

/**
 * Set account info for FTP
 * @since 5.5
 */
const CURLOPT_FTP_ACCOUNT = 10134;

/**
 * A cookie string (i.e. a single line in Netscape/Mozilla format, or a regular HTTP-style Set-Cookie header) adds that single cookie to the internal cookie store.
 * "ALL" erases all cookies held in memory.
 * "SESS" erases all session cookies held in memory.
 * "FLUSH" writes all known cookies to the file specified by CURLOPT_COOKIEJAR.
 * "RELOAD" loads all cookies from the files specified by CURLOPT_COOKIEFILE.
 * @since 5.5
 */
const CURLOPT_COOKIELIST = 10135;

/**
 * Set local port number to use for socket
 * @since 5.5
 */
const CURLOPT_LOCALPORT = 139;

/**
 * Number of additional local ports to try.
 * Pass a long. The range argument is the number of attempts libcurl will make to find a working local port number.
 * It starts with the given CURLOPT_LOCALPORT and adds one to the number for each retry.
 * @since 5.5
 */
const CURLOPT_LOCALPORTRANGE = 140;

/**
 * Command to use instead of USER with FTP.
 * @since 5.5
 */
const CURLOPT_FTP_ALTERNATIVE_TO_USER = 10147;

/**
 * Enable/disable use of the SSL session-ID cache.
 * @since 5.5
 */
const CURLOPT_SSL_SESSIONID_CACHE = 150;

/**
 * Switch off SSL again with FTP after auth.
 * @since 5.5
 */
const CURLOPT_FTP_SSL_CCC = 154;

/**
 * FALSE to get the raw HTTP response body.
 * @since 5.5
 */
const CURLOPT_HTTP_CONTENT_DECODING = 158;

/**
 * Enable/disable HTTP transfer decoding.
 * @since 5.5
 */
const CURLOPT_HTTP_TRANSFER_DECODING = 157;

/**
 * Append FTP transfer mode to URL for proxy.
 * @since 5.5
 */
const CURLOPT_PROXY_TRANSFER_MODE = 166;

/**
 * Set scope id for IPv6 addresses.
 * @since 5.5
 */
const CURLOPT_ADDRESS_SCOPE = 171;

/**
 * Specify a Certificate Revocation List file.
 * @since 5.5
 */
const CURLOPT_CRLFILE = 10169;

/**
 * Issuer SSL certificate filename.
 * @since 5.5
 */
const CURLOPT_ISSUERCERT = 10170;

/**
 * The user name to use in authentication.
 * @since 5.5
 */
const CURLOPT_USERNAME = 10173;

/**
 * Password to use in authentication.
 * @since 5.5
 */
const CURLOPT_PASSWORD = 10174;

/**
 * User name to use for proxy authentication.
 * @since 5.5
 */
const CURLOPT_PROXYUSERNAME = 10175;

/**
 * Password to use for proxy authentication.
 * @since 5.5
 */
const CURLOPT_PROXYPASSWORD = 10176;

/**
 * Disable proxy use for specific hosts.
 * @since 5.5
 */
const CURLOPT_NOPROXY = 10177;

/**
 * Set socks proxy gssapi negotiation protection.
 * @since 5.5
 */
const CURLOPT_SOCKS5_GSSAPI_NEC = 180;

/**
 * SOCKS5 proxy authentication service name.
 * @deprecated Use CURLOPT_PROXY_SERVICE_NAME instead.
 * @since 5.5
 */
const CURLOPT_SOCKS5_GSSAPI_SERVICE = 10179;

/**
 * Specify blocksize to use for TFTP data transmission.
 * @since 5.5
 */
const CURLOPT_TFTP_BLKSIZE = 178;

/**
 * File name holding the SSH known hosts.
 * @since 5.5
 */
const CURLOPT_SSH_KNOWNHOSTS = 10183;

/**
 * Enable the PRET command.
 * @since 5.5
 */
const CURLOPT_FTP_USE_PRET = 188;

/**
 * SMTP sender address.
 * @since 5.5
 */
const CURLOPT_MAIL_FROM = 10186;

/**
 * List of SMTP mail recipients.
 * @since 5.5
 */
const CURLOPT_MAIL_RCPT = 10187;

/**
 * Set the RTSP client CSEQ number.
 * @since 5.5
 */
const CURLOPT_RTSP_CLIENT_CSEQ = 193;

/**
 * Set the RTSP server CSEQ number.
 * @since 5.5
 */
const CURLOPT_RTSP_SERVER_CSEQ = 194;

/**
 * Set RTSP session ID.
 * @since 5.5
 */
const CURLOPT_RTSP_SESSION_ID = 10190;

/**
 * Set RTSP stream URI.
 * @since 5.5
 */
const CURLOPT_RTSP_STREAM_URI = 10191;

/**
 * Set RTSP Transport: header.
 * @since 5.5
 */
const CURLOPT_RTSP_TRANSPORT = 10192;

/**
 * Specify RTSP request.
 * @since 5.5
 */
const CURLOPT_RTSP_REQUEST = 189;

/**
 * Ignore content length.
 * If TRUE, ignore the Content-Length header in the HTTP response and ignore asking for or relying on it for FTP transfers.
 * This is useful for HTTP with Apache 1.x (and similar servers) which will report incorrect content length for files over 2 gigabytes.
 * If this option is used, curl will not be able to accurately report progress, and will simply stop the download when the server ends the connection.
 * It is also useful with FTP when for example the file is growing while the transfer is in progress
 * which otherwise will unconditionally cause libcurl to report error.
 * @since 5.5
 */
const CURLOPT_IGNORE_CONTENT_LENGTH = 136;

/**
 * Enables automatic decompression of HTTP downloads
 * @since 5.5
 */
const CURLOPT_ACCEPT_ENCODING = 10102;

/**
 * Ask for HTTP Transfer Encoding.
 * Adds a request for compressed Transfer Encoding in the outgoing HTTP request.
 * If the server supports this and so desires, it can respond with the HTTP response sent using a compressed Transfer-Encoding
 * that will be automatically uncompressed by libcurl on reception.
 * @since 5.5
 */
const CURLOPT_TRANSFER_ENCODING = 207;

/**
 * Set preferred DNS servers: host[:port][,host[:port]]...
 * @since 5.5
 */
const CURLOPT_DNS_SERVERS = 10211;

/**
 * Request using SSL / TLS for the transfer
 * @since 5.5
 */
const CURLOPT_USE_SSL = 119;

/**
 * Custom telnet options
 */
const CURLOPT_TELNETOPTIONS = 10070;

/**
 * The download could not be resumed because the specified offset was out of the file boundary.
 */
const CURLE_BAD_DOWNLOAD_RESUME = 36;

/**
 * A file transfer was shorter or larger than expected.
 * This happens when the server first reports an expected transfer size, and then delivers data
 * that doesn't match the previously given size.
 */
const CURLE_FTP_PARTIAL_FILE = 18;

/**
 * This is returned if CURLOPT_FAILONERROR is set TRUE and the HTTP server returns an error code that is >= 400.
 */
const CURLE_HTTP_RETURNED_ERROR = 22;

/**
 * Operation timeout. The specified time-out period was reached according to the conditions.
 */
const CURLE_OPERATION_TIMEDOUT = 28;

/**
 * Failed to match the pinned key specified with CURLOPT_PINNEDPUBLICKEY.
 */
const CURLE_SSL_PINNEDPUBKEYNOTMATCH = 90;

const CURLINFO_LASTONE = 64;

/**
 * An easy handle already added to a multi handle was attempted to get added a second time.
 */
const CURLM_ADDED_ALREADY = 7;

const CURLSHOPT_NONE = 0;

/**
 * Default value for the CURLOPT_TIMECONDITION option.
 */
const CURL_TIMECOND_NONE = 0;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * Allows no authentication.
 */
const CURLAUTH_NONE = 0;

/**
 * Problem with reading the SSL CA cert (path? access rights?)
 */
const CURLE_SSL_CACERT_BADFILE = 77;

/**
 * An unspecified error occurred during the SSH session.
 */
const CURLE_SSH = 79;

/**
 * Value for the CURLOPT_FTP_SSL_CCC option.
 * Initiate the shutdown and wait for a reply.
 */
const CURLFTPSSL_CCC_ACTIVE = 2;

/**
 * Value for the CURLOPT_FTP_SSL_CCC option.
 * Don't attempt to use CCC.
 */
const CURLFTPSSL_CCC_NONE = 0;

/**
 * Value for the CURLOPT_FTP_SSL_CCC option.
 * Do not initiate the shutdown, but wait for the server to do it. Do not send a reply.
 */
const CURLFTPSSL_CCC_PASSIVE = 1;

/**
 * Value for the CURLOPT_USE_SSL option.
 * Require SSL for all communication or fail.
 */
const CURLUSESSL_ALL = 3;

/**
 * Value for the CURLOPT_USE_SSL option.
 * Require SSL for the control connection or fail.
 */
const CURLUSESSL_CONTROL = 2;

/**
 * Value for the CURLOPT_USE_SSL option.
 * Don't attempt to use SSL.
 */
const CURLUSESSL_NONE = 0;

/**
 * Value for the CURLOPT_USE_SSL option.
 * Try using SSL, proceed as normal otherwise.
 */
const CURLUSESSL_TRY = 1;

/**
 * Convenience define that pauses both directions.
 * @since 5.5
 */
const CURLPAUSE_ALL = 5;

/**
 * Convenience define that unpauses both directions.
 * @since 5.5
 */
const CURLPAUSE_CONT = 0;

/**
 * Pause receiving data. There will be no data received on this connection until this function is called again without this bit set.
 * Thus, the write callback (CURLOPT_WRITEFUNCTION) won't be called.
 * @since 5.5
 */
const CURLPAUSE_RECV = 1;

/**
 * @since 5.5
 */
const CURLPAUSE_RECV_CONT = 0;

/**
 * Pause sending data. There will be no data sent on this connection until this function is called again without this bit set.
 * Thus, the read callback (CURLOPT_READFUNCTION) won't be called.
 * @since 5.5
 */
const CURLPAUSE_SEND = 4;

/**
 * @since 5.5
 */
const CURLPAUSE_SEND_CONT = 0;

/**
 * Read callback for data uploads.
 */
const CURL_READFUNC_PAUSE = 268435457;

/**
 * Read callback for data uploads: return to abort the transfer.
 * @since 8.6
 */
const CURL_READFUNC_ABORT = 268435456;

/**
 * Set callback for writing received data.
 */
const CURL_WRITEFUNC_PAUSE = 268435457;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 * @since 5.5
 */
const CURLPROXY_SOCKS4A = 6;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 * Proxy resolves URL hostname.
 * @since 5.5
 */
const CURLPROXY_SOCKS5_HOSTNAME = 7;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_ANY = 4294967295;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_DEFAULT = 4294967295;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_HOST = 4;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_KEYBOARD = 8;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_NONE = 0;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_PASSWORD = 2;

/**
 * Value for the CURLOPT_SSH_AUTH_TYPES option.
 */
const CURLSSH_AUTH_PUBLICKEY = 1;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * HTTP Digest authentication with an IE flavor.
 * Digest authentication is defined in RFC 2617 and is a more secure way to do authentication over public networks than
 * the regular old-fashioned Basic method.
 * The IE flavor is simply that libcurl will use a special "quirk" that IE is known to have used before version 7
 * and that some servers require the client to use.
 */
const CURLAUTH_DIGEST_IE = 16;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_IMAP = 4096;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_IMAPS = 8192;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_POP3 = 16384;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_POP3S = 32768;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTSP = 262144;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_SMTP = 65536;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_SMTPS = 131072;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * When sent by a client, this method changes the description of the session.
 * For example, if a client is using the server to record a meeting,
 * the client can use Announce to inform the server of all the meta-information about the session.
 * ANNOUNCE acts like an HTTP PUT or POST
 */
const CURL_RTSPREQ_ANNOUNCE = 3;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Used to get the low level description of a stream.
 * The application should note what formats it understands in the 'Accept:' header.
 * Unless set manually, libcurl will automatically fill in 'Accept: application/sdp'.
 * Time-condition headers will be added to Describe requests if the CURLOPT_TIMECONDITION option is active.
 */
const CURL_RTSPREQ_DESCRIBE = 2;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Retrieve a parameter from the server.
 * By default, libcurl will automatically include a Content-Type: text/parameters header on all non-empty requests
 * unless a custom one is set. GET_PARAMETER acts just like an HTTP PUT or POST
 */
const CURL_RTSPREQ_GET_PARAMETER = 8;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Used to retrieve the available methods of the server.
 * The application is responsible for parsing and obeying the response.
 * The session ID is not needed for this method.
 */
const CURL_RTSPREQ_OPTIONS = 1;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Send a Pause command to the server.
 * Use the CURLOPT_RANGE option with a single value to indicate when the stream should be halted. (e.g. npt='25')
 */
const CURL_RTSPREQ_PAUSE = 6;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Send a Play command to the server.
 * Use the CURLOPT_RANGE option to modify the playback time (e.g. 'npt=10-15').
 */
const CURL_RTSPREQ_PLAY = 5;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * This is a special request because it does not send any data to the server.
 * The application may call this function in order to receive interleaved RTP data.
 * It will return after processing one read buffer of data in order to give the application a chance to run.
 */
const CURL_RTSPREQ_RECEIVE = 11;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Used to tell the server to record a session. Use the CURLOPT_RANGE option to modify the record time.
 */
const CURL_RTSPREQ_RECORD = 10;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Set a parameter on the server.
 * By default, libcurl will automatically include a Content-Type: text/parameters header unless a custom one is set.
 * The interaction with SET_PARAMETER is much like an HTTP PUT or POST.
 */
const CURL_RTSPREQ_SET_PARAMETER = 9;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * Setup is used to initialize the transport layer for the session.
 * The application must set the desired Transport options for a session
 * by using the CURLOPT_RTSP_TRANSPORT option prior to calling setup.
 */
const CURL_RTSPREQ_SETUP = 4;

/**
 * Value for the CURLOPT_RTSP_REQUEST option.
 * This command terminates an RTSP session.
 * Simply closing a connection does not terminate the RTSP session since it is valid to control an RTSP session over different connections.
 */
const CURL_RTSPREQ_TEARDOWN = 7;

/**
 * Wildcard matching function callback.
 */
const CURLOPT_FNMATCH_FUNCTION = 20200;

/**
 * Enable directory wildcard transfers.
 */
const CURLOPT_WILDCARDMATCH = 197;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMP = 524288;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMPE = 2097152;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMPS = 8388608;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMPT = 1048576;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMPTE = 4194304;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_RTMPTS = 16777216;

/**
 * Return value for the CURLOPT_FNMATCH_FUNCTION if an error was occurred.
 */
const CURL_FNMATCHFUNC_FAIL = 2;

/**
 * Return value for the CURLOPT_FNMATCH_FUNCTION if pattern matches the string.
 */
const CURL_FNMATCHFUNC_MATCH = 0;

/**
 * Return value for the CURLOPT_FNMATCH_FUNCTION if pattern not matches the string.
 */
const CURL_FNMATCHFUNC_NOMATCH = 1;

/**
 * Value for the CURLOPT_PROTOCOLS option.
 */
const CURLPROTO_GOPHER = 33554432;

/**
 * Value for the CURLOPT_HTTPAUTH option.
 * This is a meta symbol.
 * OR this value together with a single specific auth value to force libcurl to probe for un-restricted auth and if not,
 * only that single auth algorithm is acceptable.
 */
const CURLAUTH_ONLY = 2147483648;

/**
 * Password to use for TLS authentication.
 */
const CURLOPT_TLSAUTH_PASSWORD = 10205;

/**
 * Set TLS authentication methods.
 */
const CURLOPT_TLSAUTH_TYPE = 10206;

/**
 * User name to use for TLS authentication.
 */
const CURLOPT_TLSAUTH_USERNAME = 10204;

/**
 * Value for the CURLOPT_TLSAUTH_TYPE option.
 * TLS-SRP authentication.
 * Secure Remote Password authentication for TLS is defined in RFC 5054 and provides mutual authentication if both sides have a shared secret.
 */
const CURL_TLSAUTH_SRP = 1;

/**
 * Value for the CURLOPT_GSSAPI_DELEGATION option.
 * Allow unconditional GSSAPI credential delegation.
 */
const CURLGSSAPI_DELEGATION_FLAG = 2;

/**
 * Value for the CURLOPT_GSSAPI_DELEGATION option.
 * Delegate only if the OK-AS-DELEGATE flag is set in the service ticket
 * in case this feature is supported by the GSS-API implementation.
 */
const CURLGSSAPI_DELEGATION_POLICY_FLAG = 1;

/**
 * Set allowed GSS-API delegation.
 */
const CURLOPT_GSSAPI_DELEGATION = 210;

/**
 * Timeout waiting for FTP server to connect back
 */
const CURLOPT_ACCEPTTIMEOUT_MS = 212;

/**
 * SMTP authentication address
 */
const CURLOPT_MAIL_AUTH = 10217;

/**
 * Set SSL behavior options, which is a bitmask of any of the following constants:
 * CURLSSLOPT_ALLOW_BEAST: do not attempt to use any workarounds for a security flaw in the SSL3 and TLS1.0 protocols.
 * CURLSSLOPT_NO_REVOKE: disable certificate revocation checks for those SSL backends where such behavior is present.
 * @since 5.6
 */
const CURLOPT_SSL_OPTIONS = 216;

/**
 * If set to 1, TCP keepalive probes will be sent.
 * The delay and frequency of these probes can be controlled by the CURLOPT_TCP_KEEPIDLE and CURLOPT_TCP_KEEPINTVL options,
 * provided the operating system supports them.
 * If set to 0 (default) keepalive probes are disabled.
 * @since 5.5
 */
const CURLOPT_TCP_KEEPALIVE = 213;

/**
 * Sets the delay, in seconds, that the operating system will wait while the connection is idle before sending keepalive probes,
 * if CURLOPT_TCP_KEEPALIVE is enabled. Not all operating systems support this option. The default is 60.
 * @since 5.5
 */
const CURLOPT_TCP_KEEPIDLE = 214;

/**
 * Sets the interval, in seconds, that the operating system will wait between sending keepalive probes,
 * if CURLOPT_TCP_KEEPALIVE is enabled. Not all operating systems support this option. The default is 60.
 * @since 5.5
 */
const CURLOPT_TCP_KEEPINTVL = 215;

/**
 * Value for the CURLOPT_SSL_OPTIONS option.
 * Do not attempt to use any workarounds for a security flaw in the SSL3 and TLS1.0 protocols.
 * @since 5.6
 */
const CURLSSLOPT_ALLOW_BEAST = 1;

/**
 * Supports HTTP2.
 * @since 5.5
 */
const CURL_VERSION_HTTP2 = 65536;

/**
 * Value for the CURLOPT_SSL_OPTIONS option.
 * Disable certificate revocation checks for those SSL backends where such behavior is present.
 * @since 7.0
 */
const CURLSSLOPT_NO_REVOKE = 2;

/**
 * The default protocol to use if the URL is missing a scheme name.
 * @since 7.0
 */
const CURLOPT_DEFAULT_PROTOCOL = 10238;

/**
 * Set the numerical stream weight (a number between 1 and 256).
 * @since 7.0
 */
const CURLOPT_STREAM_WEIGHT = 239;

/**
 * TRUE to not send TFTP options requests.
 * @since 7.0
 */
const CURLOPT_TFTP_NO_OPTIONS = 242;

/**
 * Connect to a specific host and port instead of the URL's host and port.
 * Accepts an array of strings with the format HOST:PORT:CONNECT-TO-HOST:CONNECT-TO-PORT.
 * @since 7.0
 */
const CURLOPT_CONNECT_TO = 10243;

/**
 * TRUE to enable TCP Fast Open.
 * @since 7.0
 */
const CURLOPT_TCP_FASTOPEN = 244;

/**
 * The server sent data libcurl couldn't parse.
 * @since 7.3
 */
const CURLE_WEIRD_SERVER_REPLY = 8;

/**
 * TRUE to keep sending the request body if the HTTP code returned is equal to or larger than 300.
 * The default action would be to stop sending and close the stream or connection. Suitable for manual NTLM authentication.
 * Most applications do not need this option.
 * @since 7.3
 */
const CURLOPT_KEEP_SENDING_ON_ERROR = 245;

/**
 * Value for the CURLOPT_SSLVERSION option.
 * @since 7.3
 */
const CURL_SSLVERSION_TLSv1_3 = 7;

/**
 * Supports HTTPS proxy.
 * @since 7.3
 */
const CURL_VERSION_HTTPS_PROXY = 2097152;

/**
 * The protocol used in the last HTTP connection. The returned value will be exactly one of the CURLPROTO_* values
 * @since 7.3
 */
const CURLINFO_PROTOCOL = 2097200;

/**
 * Supports asynchronous name lookups.
 * @since 7.3
 */
const CURL_VERSION_ASYNCHDNS = 128;

/**
 * Supports memory tracking debug capabilities.
 * @since 7.3
 */
const CURL_VERSION_CURLDEBUG = 8192;

/**
 * Supports character conversions.
 * @since 7.3
 */
const CURL_VERSION_CONV = 4096;

/**
 * libcurl was built with debug capabilities
 * @since 7.3
 */
const CURL_VERSION_DEBUG = 64;

/**
 * Supports HTTP GSS-Negotiate.
 * @since 7.3
 */
const CURL_VERSION_GSSNEGOTIATE = 32;

/**
 * Supports the IDNA.
 * @since 7.3
 */
const CURL_VERSION_IDN = 1024;

/**
 * Supports large files.
 * @since 7.3
 */
const CURL_VERSION_LARGEFILE = 512;

/**
 * Supports HTTP NTLM.
 * @since 7.3
 */
const CURL_VERSION_NTLM = 16;

/**
 * Supports the Mozilla's Public Suffix List.
 * @since 7.0
 */
const CURL_VERSION_PSL = 1048576;

/**
 * Supports for SPNEGO authentication (RFC 2478).
 * @since 7.3
 */
const CURL_VERSION_SPNEGO = 256;

/**
 * Supports SSPI. Windows-specific.
 * @since 7.3
 */
const CURL_VERSION_SSPI = 2048;

/**
 * Supports the TLS-SRP.
 * @since 7.3
 */
const CURL_VERSION_TLSAUTH_SRP = 16384;

/**
 * Supports the NTLM delegation to a winbind helper.
 * @since 7.3
 */
const CURL_VERSION_NTLM_WB = 32768;

/**
 * Supports the GSSAPI. This makes libcurl use provided functions for Kerberos and SPNEGO authentication.
 * @since 7.3
 */
const CURL_VERSION_GSSAPI = 131072;

/**
 * Supports Kerberos V5 authentication for FTP, IMAP, POP3, SMTP and SOCKSv5 proxy.
 * @since 7.3
 */
const CURL_VERSION_KERBEROS5 = 262144;

/**
 * The path to proxy Certificate Authority (CA) bundle.
 * Set the path as a string naming a file holding one or more certificates to verify the HTTPS proxy with.
 * This option is for connecting to an HTTPS proxy, not an HTTPS server.
 * Defaults set to the system path where libcurl's cacert bundle is assumed to be stored.
 * @since 7.3
 */
const CURLOPT_PROXY_CAINFO = 10246;

/**
 * The directory holding multiple CA certificates to verify the HTTPS proxy with.
 * @since 7.3
 */
const CURLOPT_PROXY_CAPATH = 10247;

/**
 * Set the file name with the concatenation of CRL (Certificate Revocation List) in PEM format
 * to use in the certificate validation that occurs during the SSL exchange.
 * @since 7.3
 */
const CURLOPT_PROXY_CRLFILE = 10260;

/**
 * Set the string be used as the password required to use the CURLOPT_PROXY_SSLKEY private key.
 * You never needed a passphrase to load a certificate but you need one to load your private key.
 * This option is for connecting to an HTTPS proxy, not an HTTPS server.
 * @since 7.3
 */
const CURLOPT_PROXY_KEYPASSWD = 10258;

/**
 * The format of your client certificate used when connecting to an HTTPS proxy. Supported formats are "PEM" and "DER", except with Secure Transport.
 * OpenSSL (versions 0.9.3 and later) and Secure Transport (on iOS 5 or later, or OS X 10.7 or later) also support "P12" for PKCS#12-encoded files.
 * Defaults to "PEM".
 * @since 7.3
 */
const CURLOPT_PROXY_SSLCERTTYPE = 10255;

/**
 * The format of your private key. Supported formats are "PEM", "DER" and "ENG".
 * @since 7.3
 */
const CURLOPT_PROXY_SSLKEYTYPE = 10257;

/**
 * One of CURL_SSLVERSION_DEFAULT, CURL_SSLVERSION_TLSv1, CURL_SSLVERSION_TLSv1_0, CURL_SSLVERSION_TLSv1_1, CURL_SSLVERSION_TLSv1_2,
 * CURL_SSLVERSION_TLSv1_3, CURL_SSLVERSION_MAX_DEFAULT, CURL_SSLVERSION_MAX_TLSv1_0, CURL_SSLVERSION_MAX_TLSv1_1,
 * CURL_SSLVERSION_MAX_TLSv1_2, CURL_SSLVERSION_MAX_TLSv1_3 or CURL_SSLVERSION_SSLv3.
 * See also CURLOPT_SSLVERSION.
 * @since 7.3
 */
const CURLOPT_PROXY_SSLVERSION = 250;

/**
 * Tusername to use for the HTTPS proxy TLS authentication method specified with the CURLOPT_PROXY_TLSAUTH_TYPE option.
 * Requires that the CURLOPT_PROXY_TLSAUTH_PASSWORD option to also be set.
 * @since 7.3
 */
const CURLOPT_PROXY_TLSAUTH_USERNAME = 10251;

/**
 * The password to use for the TLS authentication method specified with the CURLOPT_PROXY_TLSAUTH_TYPE option.
 * Requires that the CURLOPT_PROXY_TLSAUTH_USERNAME option to also be set.
 * @since 7.3
 */
const CURLOPT_PROXY_TLSAUTH_PASSWORD = 10252;

/**
 * The method of the TLS authentication used for the HTTPS connection. Supported method is "SRP".
 * Secure Remote Password (SRP) authentication for TLS provides mutual authentication if both sides have a shared secret.
 * To use TLS-SRP, you must also set the CURLOPT_PROXY_TLSAUTH_USERNAME and CURLOPT_PROXY_TLSAUTH_PASSWORD options.
 * @since 7.3
 */
const CURLOPT_PROXY_TLSAUTH_TYPE = 10253;

/**
 * Value for the CURLOPT_PROXYTYPE option.
 * Use HTTPS Proxy.
 * @since 7.3
 */
const CURLPROXY_HTTPS = 2;

/**
 * Set the pinned public key for HTTPS proxy. The string can be the file name of your pinned public key. The file format expected is "PEM" or "DER".
 * The string can also be any number of base64 encoded sha256 hashes preceded by "sha256//" and separated by ";"
 * @since 7.3
 */
const CURLOPT_PROXY_PINNEDPUBLICKEY = 10263;

/**
 * The file name of your private key used for connecting to the HTTPS proxy.
 * The default format is "PEM" and can be changed with CURLOPT_PROXY_SSLKEYTYPE.
 * (iOS and Mac OS X only) This option is ignored if curl was built against Secure Transport.
 * @since 7.3
 */
const CURLOPT_PROXY_SSLKEY = 10256;

/**
 * The list of ciphers to use for the connection to the HTTPS proxy.
 * The list must be syntactically correct, it consists of one or more cipher strings separated by colons.
 * Commas or spaces are also acceptable separators but colons are normally used, !, - and + can be used as operators.
 * @since 7.3
 */
const CURLOPT_PROXY_SSL_CIPHER_LIST = 10259;

/**
 * Set proxy SSL behavior options, which is a bitmask of any of the following constants:
 * CURLSSLOPT_ALLOW_BEAST: do not attempt to use any workarounds for a security flaw in the SSL3 and TLS1.0 protocols.
 * CURLSSLOPT_NO_REVOKE: disable certificate revocation checks for those SSL backends where such behavior is present. (curl >= 7.44.0)
 * CURLSSLOPT_NO_PARTIALCHAIN: do not accept "partial" certificate chains, which it otherwise does by default. (curl >= 7.68.0)
 * @since 7.3
 */
const CURLOPT_PROXY_SSL_OPTIONS = 261;

/**
 * Set to 2 to verify in the HTTPS proxy's certificate name fields against the proxy name.
 * When set to 0 the connection succeeds regardless of the names used in the certificate.
 * Use that ability with caution! 1 treated as a debug option in curl 7.28.0 and earlier.
 * From curl 7.28.1 to 7.65.3 CURLE_BAD_FUNCTION_ARGUMENT is returned.
 * From curl 7.66.0 onwards 1 and 2 is treated as the same value.
 * In production environments the value of this option should be kept at 2 (default value).
 * @since 7.3
 */
const CURLOPT_PROXY_SSL_VERIFYHOST = 249;

/**
 * FALSE to stop cURL from verifying the peer's certificate.
 * Alternate certificates to verify against can be specified with the CURLOPT_CAINFO option or
 * a certificate directory can be specified with the CURLOPT_CAPATH option.
 * When set to false, the peer certificate verification succeeds regardless.
 * @since 7.3
 */
const CURLOPT_PROXY_SSL_VERIFYPEER = 248;

/**
 * The file name of your client certificate used to connect to the HTTPS proxy.
 * The default format is "P12" on Secure Transport and "PEM" on other engines, and can be changed with CURLOPT_PROXY_SSLCERTTYPE.
 * With NSS or Secure Transport, this can also be the nickname of the certificate you wish to authenticate with as it is named in the security database.
 * If you want to use a file from the current directory, please precede it with "./" prefix, in order to avoid confusion with a nickname.
 * @since 7.3
 */
const CURLOPT_PROXY_SSLCERT = 10254;

/**
 * The URL scheme used for the most recent connection
 * @since 7.3
 */
const CURLINFO_SCHEME = 1048625;

/**
 * Supports UNIX sockets.
 * @since 7.0
 */
const CURL_VERSION_UNIX_SOCKETS = 524288;

/**
 * The version used in the last HTTP connection. The return value will be one of the defined
 * @since 7.3
 */
const CURLINFO_HTTP_VERSION = 2097198;

/**
 * Set a string holding the host name or dotted numerical IP address to be used as the preproxy that curl connects to before
 * it connects to the HTTP(S) proxy specified in the CURLOPT_PROXY option for the upcoming request.
 * The preproxy can only be a SOCKS proxy and it should be prefixed with [scheme]:// to specify which kind of socks is used.
 * A numerical IPv6 address must be written within [brackets]. Setting the preproxy to an empty string explicitly disables the use of a preproxy.
 * To specify port number in this string, append :[port] to the end of the host name.
 * The proxy's port number may optionally be specified with the separate option CURLOPT_PROXYPORT.
 * Defaults to using port 1080 for ...
 * @since 7.3
 */
const CURLOPT_PRE_PROXY = 10262;

/**
 * The result of the certificate verification that was requested (using the CURLOPT_PROXY_SSL_VERIFYPEER option).
 * Only used for HTTPS proxies
 * @since 7.3
 */
const CURLINFO_PROXY_SSL_VERIFYRESULT = 2097199;

/**
 * Whether to allow HTTP/0.9 responses.
 * Defaults to FALSE as of libcurl 7.66.0; formerly it defaulted to TRUE.
 * @since 7.3
 */
const CURLOPT_HTTP09_ALLOWED = 285;

/**
 * @since 7.3
 */
const CURL_VERSION_ALTSVC = 16777216;

/**
 * @since 8.1
 */
const CURLOPT_DOH_URL = 10279;

/**
 * @since 8.1
 */
const CURLOPT_ISSUERCERT_BLOB = 40295;

/**
 * @since 8.1
 */
const CURLOPT_PROXY_ISSUERCERT = 10296;

/**
 * @since 8.1
 */
const CURLOPT_PROXY_ISSUERCERT_BLOB = 40297;

/**
 * @since 8.1
 */
const CURLOPT_PROXY_SSLCERT_BLOB = 40293;

/**
 * @since 8.1
 */
const CURLOPT_PROXY_SSLKEY_BLOB = 40294;

/**
 * @since 8.1
 */
const CURLOPT_SSLCERT_BLOB = 40291;

/**
 * @since 8.1
 */
const CURLOPT_SSLKEY_BLOB = 40292;

/**
 * @since 8.2
 */
const CURLOPT_XFERINFOFUNCTION = 20219;

/**
 * @since 8.2
 */
const CURLINFO_EFFECTIVE_METHOD = 1048634;

/**
 * @since 8.2
 */
const CURLOPT_MAXFILESIZE_LARGE = 30117;

/**
 * @since 8.2
 */
const CURLFTPMETHOD_DEFAULT = 0;

/**
 * @since 8.2
 */
const CURLOPT_UPKEEP_INTERVAL_MS = 281;

/**
 * @since 8.2
 */
const CURLOPT_UPLOAD_BUFFERSIZE = 280;

/**
 * @since 8.2
 */
const CURLALTSVC_H1 = 8;

/**
 * @since 8.2
 */
const CURLALTSVC_H2 = 16;

/**
 * @since 8.2
 */
const CURLALTSVC_H3 = 32;

/**
 * @since 8.2
 */
const CURLALTSVC_READONLYFILE = 4;

/**
 * @since 8.2
 */
const CURLOPT_ALTSVC = 10287;

/**
 * @since 8.2
 */
const CURLOPT_ALTSVC_CTRL = 286;

/**
 * @since 8.2
 */
const CURLOPT_MAXAGE_CONN = 288;

/**
 * @since 8.2
 */
const CURLOPT_SASL_AUTHZID = 10289;

/**
 * @since 8.2
 */
const CURL_VERSION_HTTP3 = 33554432;

/**
 * @since 8.2
 */
const CURLINFO_RETRY_AFTER = 6291513;

/**
 * @since 8.2
 */
const CURLMOPT_MAX_CONCURRENT_STREAMS = 16;

/**
 * @since 8.2
 */
const CURLSSLOPT_NO_PARTIALCHAIN = 4;

/**
 * @since 8.2
 */
const CURLOPT_MAIL_RCPT_ALLLOWFAILS = 290;

/**
 * @since 8.2
 */
const CURLSSLOPT_REVOKE_BEST_EFFORT = 8;

/**
 * @since 8.2
 */
const CURLPROTO_MQTT = 268435456;

/**
 * @since 8.2
 */
const CURLSSLOPT_NATIVE_CA = 16;

/**
 * @since 8.2
 */
const CURL_VERSION_UNICODE = 134217728;

/**
 * @since 8.2
 */
const CURL_VERSION_ZSTD = 67108864;

/**
 * @since 8.2
 */
const CURLE_PROXY = 97;

/**
 * @since 8.2
 */
const CURLINFO_PROXY_ERROR = 2097211;

/**
 * @since 8.2
 */
const CURLOPT_SSL_EC_CURVES = 10298;

/**
 * @since 8.2
 */
const CURLPX_BAD_ADDRESS_TYPE = 1;

/**
 * @since 8.2
 */
const CURLPX_BAD_VERSION = 2;

/**
 * @since 8.2
 */
const CURLPX_CLOSED = 3;

/**
 * @since 8.2
 */
const CURLPX_GSSAPI = 4;

/**
 * @since 8.2
 */
const CURLPX_GSSAPI_PERMSG = 5;

/**
 * @since 8.2
 */
const CURLPX_GSSAPI_PROTECTION = 6;

/**
 * @since 8.2
 */
const CURLPX_IDENTD = 7;

/**
 * @since 8.2
 */
const CURLPX_IDENTD_DIFFER = 8;

/**
 * @since 8.2
 */
const CURLPX_LONG_HOSTNAME = 9;

/**
 * @since 8.2
 */
const CURLPX_LONG_PASSWD = 10;

/**
 * @since 8.2
 */
const CURLPX_LONG_USER = 11;

/**
 * @since 8.2
 */
const CURLPX_NO_AUTH = 12;

/**
 * @since 8.2
 */
const CURLPX_OK = 0;

/**
 * @since 8.2
 */
const CURLPX_RECV_ADDRESS = 13;

/**
 * @since 8.2
 */
const CURLPX_RECV_AUTH = 14;

/**
 * @since 8.2
 */
const CURLPX_RECV_CONNECT = 15;

/**
 * @since 8.2
 */
const CURLPX_RECV_REQACK = 16;

/**
 * @since 8.2
 */
const CURLPX_REPLY_ADDRESS_TYPE_NOT_SUPPORTED = 17;

/**
 * @since 8.2
 */
const CURLPX_REPLY_COMMAND_NOT_SUPPORTED = 18;

/**
 * @since 8.2
 */
const CURLPX_REPLY_CONNECTION_REFUSED = 19;

/**
 * @since 8.2
 */
const CURLPX_REPLY_GENERAL_SERVER_FAILURE = 20;

/**
 * @since 8.2
 */
const CURLPX_REPLY_HOST_UNREACHABLE = 21;

/**
 * @since 8.2
 */
const CURLPX_REPLY_NETWORK_UNREACHABLE = 22;

/**
 * @since 8.2
 */
const CURLPX_REPLY_NOT_ALLOWED = 23;

/**
 * @since 8.2
 */
const CURLPX_REPLY_TTL_EXPIRED = 24;

/**
 * @since 8.2
 */
const CURLPX_REPLY_UNASSIGNED = 25;

/**
 * @since 8.2
 */
const CURLPX_REQUEST_FAILED = 26;

/**
 * @since 8.2
 */
const CURLPX_RESOLVE_HOST = 27;

/**
 * @since 8.2
 */
const CURLPX_SEND_CONNECT = 29;

/**
 * @since 8.2
 */
const CURLPX_SEND_AUTH = 28;

/**
 * @since 8.2
 */
const CURLPX_SEND_REQUEST = 30;

/**
 * @since 8.2
 */
const CURLPX_UNKNOWN_FAIL = 31;

/**
 * @since 8.2
 */
const CURLPX_UNKNOWN_MODE = 32;

/**
 * @since 8.2
 */
const CURLPX_USER_REJECTED = 33;

/**
 * @since 8.2
 */
const CURLHSTS_ENABLE = 1;

/**
 * @since 8.2
 */
const CURLHSTS_READONLYFILE = 2;

/**
 * @since 8.2
 */
const CURLOPT_HSTS = 10300;

/**
 * @since 8.2
 */
const CURLOPT_HSTS_CTRL = 299;

/**
 * @since 8.2
 */
const CURL_VERSION_HSTS = 268435456;

/**
 * @since 8.2
 */
const CURLAUTH_AWS_SIGV4 = 128;

/**
 * @since 8.2
 */
const CURLOPT_AWS_SIGV4 = 10305;

/**
 * @since 8.2
 */
const CURLINFO_REFERER = 1048636;

/**
 * @since 8.2
 */
const CURLOPT_DOH_SSL_VERIFYHOST = 307;

/**
 * @since 8.2
 */
const CURLOPT_DOH_SSL_VERIFYPEER = 306;

/**
 * @since 8.2
 */
const CURLOPT_DOH_SSL_VERIFYSTATUS = 308;

/**
 * @since 8.2
 */
const CURL_VERSION_GSASL = 536870912;

/**
 * @since 8.2
 */
const CURLOPT_CAINFO_BLOB = 40309;

/**
 * @since 8.2
 */
const CURLOPT_PROXY_CAINFO_BLOB = 40310;

/**
 * @since 8.2
 */
const CURLSSLOPT_AUTO_CLIENT_CERT = 32;

/**
 * @since 8.2
 */
const CURLOPT_MAXLIFETIME_CONN = 314;

/**
 * @since 8.2
 */
const CURLOPT_SSH_HOST_PUBLIC_KEY_SHA256 = 10311;

/**
 * @since 8.4
 */
const CURL_HTTP_VERSION_3 = 30;

/**
 * @since 8.4
 */
const CURL_HTTP_VERSION_3ONLY = 31;

/**
 * @since 8.4
 */
const CURLOPT_PREREQFUNCTION = 20312;

/**
 * @since 8.4
 */
const CURL_PREREQFUNC_OK = 0;

/**
 * @since 8.4
 */
const CURL_PREREQFUNC_ABORT = 1;

/**
 * @since 8.4
 */
const CURLOPT_TCP_KEEPCNT = 326;

/**
 * @since 8.4
 */
const CURLOPT_SERVER_RESPONSE_TIMEOUT = 112;

/**
 * @since 8.4
 */
const CURLOPT_DEBUGFUNCTION = 1;

/**
 * @since 8.4
 */
const CURLINFO_TEXT = 0;

/**
 * @since 8.4
 */
const CURLINFO_HEADER_IN = 1;

/**
 * @since 8.4
 */
const CURLINFO_DATA_IN = 3;

/**
 * @since 8.4
 */
const CURLINFO_DATA_OUT = 4;

/**
 * @since 8.4
 */
const CURLINFO_SSL_DATA_OUT = 5;

/**
 * @since 8.4
 */
const CURLINFO_SSL_DATA_IN = 6;

/**
 * @since 8.4
 */
const CURLINFO_POSTTRANSFER_TIME_T = 6291523;

const CURLFOLLOW_ALL = 1;

const CURLFOLLOW_OBEYCODE = 2;

const CURLFOLLOW_FIRSTONLY = 3;

const CURLINFO_HTTPAUTH_USED = 2097221;

const CURLINFO_PROXYAUTH_USED = 2097222;

const CURLINFO_QUEUE_TIME_T = 6291521;

const CURLINFO_USED_PROXY = 2097218;

const CURLINFO_CONN_ID = 6291520;

const CURLOPT_SSL_SIGNATURE_ALGORITHMS = 10328;

/**
 * @since 8.6
 */
const CURLOPT_SEEKFUNCTION = 20167;

/**
 * @since 8.6
 */
const CURL_SEEKFUNC_OK = 0;

/**
 * @since 8.6
 */
const CURL_SEEKFUNC_FAIL = 1;

/**
 * @since 8.6
 */
const CURL_SEEKFUNC_CANTSEEK = 2;
