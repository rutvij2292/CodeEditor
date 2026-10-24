<?php

/**
 * Runs the equivalent of the select() system call on the given
 * arrays of streams with a timeout specified by tv_sec and tv_usec
 * @param array|null &$read The streams listed in the read array will be watched to see if characters become available for reading (more precisely, to see if a read will not block - in particular, a stream resource is also ready on end-of-file, in which case an fread will return a zero length string).
 * @param array|null &$write The streams listed in the write array will be watched to see if a write will not block.
 * @param array|null &$except The streams listed in the except array will be watched for high priority exceptional ("out-of-band") data arriving. When stream_select returns, the arrays read, write and except are modified to indicate which stream resource(s) actually changed status. You do not need to ...
 * @param int|null $seconds The tv_sec and tv_usec together form the timeout parameter, tv_sec specifies the number of seconds while tv_usec the number of microseconds. The timeout is an upper bound on the amount of time that stream_select will wait before it returns. If tv_sec and tv_usec are both ...
 * @param int $microseconds [optional] See tv_sec description.
 * @return int|false On success stream_select returns the number of stream resources contained in the modified arrays, which may be zero if the timeout expires before anything interesting happens. On error false is returned and a warning raised (this can happen if the system call is interrupted by an ...
 */
function stream_select(
    ?array &$read,
    ?array &$write,
    ?array &$except,
    ?int $seconds,
    int|null $microseconds = null
): int|false {}

/**
 * Create a stream context
 * @param null|array $options [optional] Must be an associative array of associative arrays in the format $arr['wrapper']['option'] = $value. Default to an empty array.
 * @param null|array $params [optional] Must be an associative array in the format $arr['parameter'] = $value. Refer to context parameters for a listing of standard stream parameters.
 * @return resource A stream context resource.
 */
function stream_context_create(?array $options = null, ?array $params = null) {}

/**
 * Set parameters for a stream/wrapper/context
 * @param resource $context The stream or context to apply the parameters too.
 * @param array $params An array of parameters to set. params should be an associative array of the structure: $params['paramname'] = "paramvalue";.
 * @return bool true on success or false on failure.
 */
function stream_context_set_params($context, array $params): bool {}

/**
 * Retrieves parameters from a context
 * @param resource $context A stream resource or a context resource
 * @return array an associate array containing all context options and parameters.
 */
function stream_context_get_params($context): array {}

/**
 * Sets an option for a stream/wrapper/context
 * @param resource $context The stream or context resource to apply the options too.
 * @param string $wrapper_or_options
 * @param string $option_name
 * @param mixed $value
 * @return bool true on success or false on failure.
 */
function stream_context_set_option($context, string $wrapper_or_options, string $option_name, mixed $value): bool {}

/**
 * Sets options on the specified context
 * @since 8.3
 */
function stream_context_set_options($context, array $options): bool {}

/**
 * Retrieve options for a stream/wrapper/context
 * @param resource $stream_or_context The stream or context to get options from
 * @return array an associative array with the options.
 */
function stream_context_get_options($stream_or_context): array {}

/**
 * Retreive the default stream context
 * @param null|array $options [optional] options must be an associative array of associative arrays in the format $arr['wrapper']['option'] = $value. As of PHP 5.3.0, the stream_context_set_default function can be used to set the default context.
 * @return resource A stream context resource.
 */
function stream_context_get_default(?array $options = null) {}

/**
 * Set the default stream context
 * @param array $options The options to set for the default context. options must be an associative array of associative arrays in the format $arr['wrapper']['option'] = $value.
 * @return resource the default stream context.
 */
function stream_context_set_default(array $options) {}

/**
 * Attach a filter to a stream
 * @param resource $stream The target stream.
 * @param string $filter_name The filter name.
 * @param int $mode By default, stream_filter_prepend will attach the filter to the read filter chain if the file was opened for reading (i.e. File Mode: r, and/or +). The filter will also be attached to the write filter chain if the file was opened for writing (i.e. File Mode: w, a, and/or +). ...
 * @param mixed $params [optional] This filter will be added with the specified params to the beginning of the list and will therefore be called first during stream operations. To add a filter to the end of the list, use stream_filter_append.
 * @return resource|false a resource which can be used to refer to this filter instance during a call to stream_filter_remove.
 */
function stream_filter_prepend($stream, string $filter_name, int $mode = 0, mixed $params) {}

/**
 * Attach a filter to a stream
 * @param resource $stream The target stream.
 * @param string $filter_name The filter name.
 * @param int $mode By default, stream_filter_append will attach the filter to the read filter chain if the file was opened for reading (i.e. File Mode: r, and/or +). The filter will also be attached to the write filter chain if the file was opened for writing (i.e. File Mode: w, a, and/or +). ...
 * @param mixed $params [optional] This filter will be added with the specified params to the end of the list and will therefore be called last during stream operations. To add a filter to the beginning of the list, use stream_filter_prepend.
 * @return resource|false a resource which can be used to refer to this filter instance during a call to stream_filter_remove.
 */
function stream_filter_append($stream, string $filter_name, int $mode = 0, mixed $params) {}

/**
 * Remove a filter from a stream
 * @param resource $stream_filter The stream filter to be removed.
 * @return bool true on success or false on failure.
 */
function stream_filter_remove($stream_filter): bool {}

/**
 * Open Internet or Unix domain socket connection
 * @param string $address Address to the socket to connect to.
 * @param int &$error_code [optional] Will be set to the system level error number if connection fails.
 * @param string &$error_message [optional] Will be set to the system level error message if the connection fails.
 * @param float|null $timeout [optional] Number of seconds until the connect() system call should timeout. This parameter only applies when not making asynchronous connection attempts. To set a timeout for reading/writing data over the socket, use the stream_set_timeout, as the timeout only applies ...
 * @param int $flags [optional] Bitmask field which may be set to any combination of connection flags. Currently the select of connection flags is limited to STREAM_CLIENT_CONNECT (default), STREAM_CLIENT_ASYNC_CONNECT and STREAM_CLIENT_PERSISTENT.
 * @param resource $context [optional] A valid context resource created with stream_context_create.
 * @return resource|false On success a stream resource is returned which may be used together with the other file functions (such as fgets, fgetss, fwrite, fclose, and feof), false on failure.
 */
function stream_socket_client(string $address, &$error_code = null, &$error_message = null, ?float $timeout = null, int $flags = STREAM_CLIENT_CONNECT, $context = null) {}

/**
 * Create an Internet or Unix domain server socket
 * @param string $address The type of socket created is determined by the transport specified using standard URL formatting: transport://target. For Internet Domain sockets (AF_INET) such as TCP and UDP, the target portion of the remote_socket parameter should consist of a hostname or IP address ...
 * @param int &$error_code [optional] If the optional errno and errstr arguments are present they will be set to indicate the actual system level error that occurred in the system-level socket(), bind(), and listen() calls. If the value returned in errno is 0 and the function returned false, it is an ...
 * @param string &$error_message [optional] See errno description.
 * @param int $flags [optional] A bitmask field which may be set to any combination of socket creation flags. For UDP sockets, you must use STREAM_SERVER_BIND as the flags parameter.
 * @param resource $context [optional]
 * @return resource|false the created stream, or false on error.
 */
function stream_socket_server(string $address, &$error_code = null, &$error_message = null, int $flags = STREAM_SERVER_BIND|STREAM_SERVER_LISTEN, $context = null) {}

/**
 * Accept a connection on a socket created by stream_socket_server
 * @param resource $socket The server socket to accept a connection from.
 * @param float|null $timeout [optional] Override the default socket accept timeout. Time should be given in seconds.
 * @param string &$peer_name [optional] Will be set to the name (address) of the client which connected, if included and available from the selected transport. Can also be determined later using stream_socket_get_name.
 * @return resource|false Returns a stream to the accepted socket connection or FALSE on failure.
 */
function stream_socket_accept($socket, ?float $timeout = null, &$peer_name = null) {}

/**
 * Retrieve the name of the local or remote sockets
 * @param resource $socket The socket to get the name of.
 * @param bool $remote If set to true the remote socket name will be returned, if set to false the local socket name will be returned.
 * @return string|false The name of the socket or false on error.
 */
function stream_socket_get_name($socket, bool $remote): string|false {}

/**
 * Receives data from a socket, connected or not
 * @param resource $socket The remote socket.
 * @param int $length The number of bytes to receive from the socket.
 * @param int $flags The value of flags can be any combination of the following: Possible values for flags STREAM_OOB Process OOB (out-of-band) data. STREAM_PEEK Retrieve data from the socket, but do not consume the buffer. Subsequent calls to fread or stream_socket_recvfrom will see the same data.
 * @param string &$address [optional] If address is provided it will be populated with the address of the remote socket.
 * @return string|false the read data, as a string, or false on error
 */
function stream_socket_recvfrom($socket, int $length, int $flags = 0, &$address = null): string|false {}

/**
 * Sends a message to a socket, whether it is connected or not
 * @param resource $socket The socket to send data to.
 * @param string $data The data to be sent.
 * @param int $flags The value of flags can be any combination of the following: possible values for flags STREAM_OOB Process OOB (out-of-band) data.
 * @param string $address The address specified when the socket stream was created will be used unless an alternate address is specified in address. If specified, it must be in dotted quad (or [ipv6]) format.
 * @return int|false a result code, as an integer.
 */
function stream_socket_sendto($socket, string $data, int $flags = 0, string $address = ''): int|false {}

/**
 * Turns encryption on/off on an already connected socket
 * @param resource $stream The stream resource.
 * @param bool $enable Enable/disable cryptography on the stream.
 * @param int|null $crypto_method [optional] Setup encryption on the stream. Valid methods are: STREAM_CRYPTO_METHOD_SSLv2_CLIENT
 * @param resource $session_stream [optional] Seed the stream with settings from session_stream.
 * @return bool|int true on success, false if negotiation has failed or 0 if there isn't enough data and you should try again (only for non-blocking sockets).
 */
function stream_socket_enable_crypto($stream, bool $enable, ?int $crypto_method = null, $session_stream = null): int|bool {}

/**
 * Shutdown a full-duplex connection
 * @param resource $stream An open stream (opened with stream_socket_client, for example)
 * @param int $mode One of the following constants: STREAM_SHUT_RD (disable further receptions), STREAM_SHUT_WR (disable further transmissions) or STREAM_SHUT_RDWR (disable further receptions and transmissions).
 * @return bool true on success or false on failure.
 * @since 5.2
 */
function stream_socket_shutdown($stream, int $mode): bool {}

/**
 * Creates a pair of connected, indistinguishable socket streams
 * @param int $domain The protocol family to be used: STREAM_PF_INET, STREAM_PF_INET6 or STREAM_PF_UNIX
 * @param int $type The type of communication to be used: STREAM_SOCK_DGRAM, STREAM_SOCK_RAW, STREAM_SOCK_RDM, STREAM_SOCK_SEQPACKET or STREAM_SOCK_STREAM
 * @param int $protocol The protocol to be used: STREAM_IPPROTO_ICMP, STREAM_IPPROTO_IP, STREAM_IPPROTO_RAW, STREAM_IPPROTO_TCP or STREAM_IPPROTO_UDP
 * @return array|false an array with the two socket resources on success, or false on failure.
 */
function stream_socket_pair(int $domain, int $type, int $protocol): array|false {}

/**
 * Copies data from one stream to another
 * @param resource $from The source stream
 * @param resource $to The destination stream
 * @param int|null $length [optional] Maximum bytes to copy
 * @param int $offset The offset where to start to copy data
 * @return int|false the total count of bytes copied, or false on failure.
 */
function stream_copy_to_stream($from, $to, ?int $length = null, int $offset = 0): int|false {}

/**
 * Reads remainder of a stream into a string
 * @param resource $stream A stream resource (e.g. returned from fopen)
 * @param int|null $length The maximum bytes to read. Defaults to -1 (read all the remaining buffer).
 * @param int $offset [optional] Seek to the specified offset before reading.
 * @return string|false a string or false on failure.
 */
function stream_get_contents($stream, ?int $length = null, int $offset = -1): string|false {}

/**
 * Tells whether the stream supports locking.
 * @param resource $stream The stream to check.
 * @return bool true on success or false on failure.
 */
function stream_supports_lock($stream): bool {}

/**
 * Gets line from file pointer and parse for CSV fields
 * @param resource $stream A valid file pointer to a file successfully opened by fopen, popen, or fsockopen.
 * @param int|null $length Must be greater than the longest line (in characters) to be found in the CSV file (allowing for trailing line-end characters). It became optional in PHP 5. Omitting this parameter (or setting it to 0 in PHP 5.0.4 and later) the maximum line length is not limited, which is ...
 * @param string $separator [optional] Set the field delimiter (one character only).
 * @param string $enclosure [optional] Set the field enclosure character (one character only).
 * @param string $escape [optional] Set the escape character (one character only). Defaults as a backslash.
 * @return array|false|null an indexed array containing the fields read. A blank line in a CSV file will be returned as an array comprising a single null field, and will not be treated as an error. fgetcsv returns null if an invalid handle is supplied or false on other errors, including end of file.
 * @throws \ValueError Throws a ValueError if separator or enclosure is not one byte long. Throws a ValueError if escape is not one byte long or the empty string.
 */
function fgetcsv($stream, ?int $length = null, string $separator = ',', string $enclosure = '"', string $escape = '\\'): array|false {}

/**
 * Format line as CSV and write to file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @param array $fields An array of values.
 * @param string $separator [optional] The optional delimiter parameter sets the field delimiter (one character only).
 * @param string $enclosure [optional] The optional enclosure parameter sets the field enclosure (one character only).
 * @param string $escape [optional] The optional escape_char parameter sets the escape character (one character only).
 * @param string $eol The optional eol parameter sets a custom End of Line sequence.
 * @return int|false the length of the written string or false on failure.
 */
function fputcsv(
    $stream,
    array $fields,
    string $separator = ",",
    string $enclosure = '"',
    string $escape = "\\",
    string $eol = "\n"
): int|false {}

/**
 * Portable advisory file locking
 * @param resource $stream An open file pointer.
 * @param int $operation operation is one of the following: LOCK_SH to acquire a shared lock (reader).
 * @param int &$would_block [optional] The optional third argument is set to 1 if the lock would block (EWOULDBLOCK errno condition).
 * @return bool true on success or false on failure.
 */
function flock($stream, int $operation, &$would_block = null): bool {}

/**
 * Extracts all meta tag content attributes from a file and returns an array
 * @param string $filename The path to the HTML file, as a string. This can be a local file or an URL. What get_meta_tags parses <meta name="author" content="name"> <meta name="keywords" content="php documentation"> <meta name="DESCRIPTION" content="a php manual"> <meta name="geo.position" ...
 * @param bool $use_include_path [optional] Setting use_include_path to true will result in PHP trying to open the file along the standard include path as per the include_path directive. This is used for local files, not URLs.
 * @return array|false an array with all the parsed meta tags. The value of the name property becomes the key, the value of the content property becomes the value of the returned array, so you can easily use standard array functions to traverse it or access single values. Special characters in the ...
 */
function get_meta_tags(string $filename, bool $use_include_path = false): array|false {}

/**
 * Sets write file buffering on the given stream
 * @param resource $stream The file pointer.
 * @param int $size The number of bytes to buffer. If buffer is 0 then write operations are unbuffered. This ensures that all writes with fwrite are completed before other processes are allowed to write to that output stream.
 * @return int 0 on success, or EOF if the request cannot be honored.
 * @see stream_set_read_buffer()
 */
function stream_set_write_buffer($stream, int $size): int {}

/**
 * Sets read file buffering on the given stream
 * @param resource $stream The file pointer.
 * @param int $size The number of bytes to buffer. If buffer is 0 then write operations are unbuffered. This ensures that all writes with fwrite are completed before other processes are allowed to write to that output stream.
 * @return int 0 on success, or EOF if the request cannot be honored.
 * @see stream_set_write_buffer()
 */
function stream_set_read_buffer($stream, int $size): int {}

/**
 * Alias:
 * stream_set_write_buffer
 * Sets the buffering for write operations on the given stream to buffer bytes.
 * Output using fwrite() is normally buffered at 8K.
 * This means that if there are two processes wanting to write to the same output stream (a file),
 * each is paused after 8K of data to allow the other to write.
 * @param resource $stream The file pointer.
 * @param int $size The number of bytes to buffer. If buffer is 0 then write operations are unbuffered. This ensures that all writes with fwrite() are completed before other processes are allowed to write to that output stream.
 * @return int
 */
function set_file_buffer($stream, int $size): int {}

/**
 * Alias:
 * stream_set_blocking
 * Sets blocking or non-blocking mode on a stream.
 * This function works for any stream that supports non-blocking mode (currently, regular files and socket streams)
 * @param resource $socket
 * @param bool $mode If mode is FALSE, the given stream will be switched to non-blocking mode, and if TRUE, it will be switched to blocking mode. This affects calls like fgets() and fread() that read from the stream. In non-blocking mode an fgets() call will always return right away while in blocking ...
 * @return bool Returns TRUE on success or FALSE on failure.
 * @removed 7.0
 * @see stream_set_blocking()
 * @deprecated
 */
function set_socket_blocking($socket, bool $mode): bool {}

/**
 * Set blocking/non-blocking mode on a stream
 * @param resource $stream The stream.
 * @param bool $enable If mode is FALSE, the given stream will be switched to non-blocking mode, and if TRUE, it will be switched to blocking mode. This affects calls like fgets and fread that read from the stream. In non-blocking mode an fgets call will always return right away while in blocking mode ...
 * @return bool true on success or false on failure.
 */
function stream_set_blocking($stream, bool $enable): bool {}

/**
 * Alias:
 * stream_set_blocking
 * @param resource $stream The stream.
 * @param bool $enable If mode is FALSE, the given stream will be switched to non-blocking mode, and if TRUE, it will be switched to blocking mode. This affects calls like fgets and fread that read from the stream. In non-blocking mode an fgets call will always return right away while in blocking mode ...
 * @return bool true on success or false on failure.
 */
function socket_set_blocking($stream, bool $enable): bool {}

/**
 * Retrieves header/meta data from streams/file pointers
 * @param resource $stream The stream can be any stream created by fopen, fsockopen and pfsockopen.
 * @return array The result array contains the following items: timed_out (bool) - true if the stream timed out while waiting for data on the last call to fread or fgets. blocked (bool) - true if the stream is in blocking IO mode. See stream_set_blocking. eof (bool) - true if the stream has reached ...
 */
function stream_get_meta_data($stream): array {}

/**
 * Gets line from stream resource up to a given delimiter
 * @param resource $stream A valid file handle.
 * @param int $length The number of bytes to read from the handle.
 * @param string $ending An optional string delimiter.
 * @return string|false a string of up to length bytes read from the file pointed to by handle. If an error occurs, returns false.
 */
function stream_get_line($stream, int $length, string $ending = ''): string|false {}

/**
 * Register a URL wrapper implemented as a PHP class
 * @param string $protocol The wrapper name to be registered.
 * @param string $class The classname which implements the protocol.
 * @param int $flags Should be set to STREAM_IS_URL if protocol is a URL protocol. Default is 0, local stream.
 * @return bool true on success or false on failure. stream_wrapper_register will return false if the protocol already has a handler.
 */
function stream_wrapper_register(string $protocol, string $class, int $flags = 0): bool {}

/**
 * Alias:
 * stream_wrapper_register
 * Register a URL wrapper implemented as a PHP class
 * @param string $protocol The wrapper name to be registered.
 * @param string $class The classname which implements the protocol.
 * @param int $flags [optional] Should be set to STREAM_IS_URL if protocol is a URL protocol. Default is 0, local stream.
 * @return bool true on success or false on failure. stream_wrapper_register will return false if the protocol already has a handler.
 */
function stream_register_wrapper(string $protocol, string $class, int $flags = 0): bool {}

/**
 * Resolve filename against the include path according to the same rules as fopen()/include().
 * @param string $filename The filename to resolve.
 * @return string|false containing the resolved absolute filename, or FALSE on failure.
 * @since 5.3
 */
function stream_resolve_include_path(string $filename): string|false {}

/**
 * Unregister a URL wrapper
 * @param string $protocol
 * @return bool true on success or false on failure.
 */
function stream_wrapper_unregister(string $protocol): bool {}

/**
 * Restores a previously unregistered built-in wrapper
 * @param string $protocol
 * @return bool true on success or false on failure.
 */
function stream_wrapper_restore(string $protocol): bool {}

/**
 * Retrieve list of registered streams
 * @return list<string> an indexed array containing the name of all stream wrappers available on the running system.
 */
function stream_get_wrappers(): array {}

/**
 * Retrieve list of registered socket transports
 * @return list<string> an indexed array of socket transports names.
 */
function stream_get_transports(): array {}

/**
 * Checks if a stream is a local stream
 * @param mixed $stream The stream resource or URL to check.
 * @return bool true on success or false on failure.
 * @since 5.2
 */
function stream_is_local($stream): bool {}

/**
 * Fetches all the headers sent by the server in response to an HTTP request
 * @param string $url The target URL.
 * @param bool $associative [optional] If the optional format parameter is set to true, get_headers parses the response and sets the array's keys.
 * @param resource $context [optional]
 * @return array|false an indexed or associative array with the headers, or false on failure.
 */
function get_headers(
    string $url,
    bool $associative = false,
    $context = null
): array|false {}

/**
 * Set timeout period on a stream
 * @param resource $stream The target stream.
 * @param int $seconds The seconds part of the timeout to be set.
 * @param int $microseconds The microseconds part of the timeout to be set.
 * @return bool true on success or false on failure.
 */
function stream_set_timeout(
    $stream,
    int $seconds,
    int $microseconds = 0
): bool {}

/**
 * Alias:
 * stream_set_timeout
 * Set timeout period on a stream
 * @param resource $stream The target stream.
 * @param int $seconds The seconds part of the timeout to be set.
 * @param int $microseconds The microseconds part of the timeout to be set.
 * @return bool true on success or false on failure.
 */
function socket_set_timeout(
    $stream,
    int $seconds,
    int $microseconds = 0
): bool {}

/**
 * Alias:
 * stream_get_meta_data
 * Retrieves header/meta data from streams/file pointers
 * @param resource $stream The stream can be any stream created by fopen, fsockopen and pfsockopen.
 * @return array The result array contains the following items: timed_out (bool) - true if the stream timed out while waiting for data on the last call to fread or fgets. blocked (bool) - true if the stream is in blocking IO mode. See stream_set_blocking. eof (bool) - true if the stream has reached ...
 */
function socket_get_status($stream): array {}

/**
 * Returns canonicalized absolute pathname
 * @param string $path The path being checked.
 * @return string|false the canonicalized absolute pathname on success. The resulting path will have no symbolic link, '/./' or '/../' components. realpath returns false on failure, e.g. if the file does not exist.
 */
function realpath(string $path): string|false {}

/**
 * Match filename against a pattern
 * @param string $pattern The shell wildcard pattern.
 * @param string $filename The tested string. This function is especially useful for filenames, but may also be used on regular strings. The average user may be used to shell patterns or at least in their simplest form to '?' and '*' wildcards so using fnmatch instead of preg_match for frontend search ...
 * @param int $flags The value of flags can be any combination of the following flags, joined with the binary OR (|) operator. A list of possible flags for fnmatch Flag Description FNM_NOESCAPE Disable backslash escaping. FNM_PATHNAME Slash in string only matches slash in the given pattern. FNM_PERIOD ...
 * @return bool true if there is a match, false otherwise.
 */
function fnmatch(string $pattern, string $filename, int $flags = 0): bool {}
