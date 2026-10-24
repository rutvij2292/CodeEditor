<?php

/**
 * Get array with contents of getaddrinfo about the given hostname.
 * @param string $host Hostname to search.
 * @param string $service [optional] The service to connect to. If service is a name, it is translated to the corresponding port number.
 * @param array $hints Hints provide criteria for selecting addresses returned. You may specify the hints as defined by getadrinfo.
 * @return AddressInfo[]|false of AddrInfo resource handles that can be used with the other socket_addrinfo functions.
 * @since 7.2
 */
function socket_addrinfo_lookup(string $host, ?string $service = null, array $hints = []): array|false {}

/**
 * Create a Socket resource, and connect it to the provided AddrInfo resource.
 *
 * The return value of this function may be used with the rest of the socket functions.
 * @param resource|AddressInfo $address Resource created from socket_addrinfo_lookup()
 * @return resource|Socket|null|false Socket resource on success or NULL on failure.
 * @since 7.2
 */
function socket_addrinfo_connect(AddressInfo $address): Socket|false {}

/**
 * Create a Socket resource, and bind it to the provided AddrInfo resource.
 *
 * The return value of this function may be used with socket_listen().
 * @param resource|AddressInfo $address Resource created from socket_addrinfo_lookup()
 * @return resource|Socket|null|false Socket resource on success or NULL on failure.
 * @since 7.2
 */
function socket_addrinfo_bind(AddressInfo $address): Socket|false {}

/**
 * Get information about addrinfo
 * @param resource|AddressInfo $address Resource created from socket_addrinfo_lookup()
 * @return array containing the fields in the addrinfo structure.
 * @since 7.2
 */
function socket_addrinfo_explain(AddressInfo $address): array {}

/**
 * Runs the select() system call on the given arrays of sockets with a specified timeout
 * @param array|null &$read The sockets listed in the read array will be watched to see if characters become available for reading (more precisely, to see if a read will not block - in particular, a socket resource is also ready on end-of-file, in which case a socket_read will return a zero length ...
 * @param array|null &$write The sockets listed in the write array will be watched to see if a write will not block.
 * @param array|null &$except The sockets listed in the except array will be watched for exceptions.
 * @param int|null $seconds The tv_sec and tv_usec together form the timeout parameter. The timeout is an upper bound on the amount of time elapsed before socket_select return. tv_sec may be zero , causing socket_select to return immediately. This is useful for polling. If tv_sec is NULL (no timeout), ...
 * @param int $microseconds [optional]
 * @return int|false On success socket_select returns the number of socket resources contained in the modified arrays, which may be zero if the timeout expires before anything interesting happens. On error FALSE is returned. The error code can be retrieved with socket_last_error. Be sure to use the ...
 */
function socket_select(?array &$read, ?array &$write, ?array &$except, ?int $seconds, int $microseconds = 0): int|false {}

/**
 * Create a socket (endpoint for communication)
 * @param int $domain The domain parameter specifies the protocol family to be used by the socket. Available address/protocol families Domain Description AF_INET IPv4 Internet based protocols. TCP and UDP are common protocols of this protocol family. AF_INET6 IPv6 Internet based protocols. TCP and UDP ...
 * @param int $type The type parameter selects the type of communication to be used by the socket. Available socket types Type Description SOCK_STREAM Provides sequenced, reliable, full-duplex, connection-based byte streams. An out-of-band data transmission mechanism may be supported. The TCP protocol ...
 * @param int $protocol The protocol parameter sets the specific protocol within the specified domain to be used when communicating on the returned socket. The proper value can be retrieved by name by using getprotobyname. If the desired protocol is TCP, or UDP the corresponding constants SOL_TCP, and ...
 * @return resource|Socket|false socket_create returns a socket resource on success, or FALSE on error. The actual error code can be retrieved by calling socket_last_error. This error code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_create(int $domain, int $type, int $protocol): Socket|false {}

/**
 * Export a socket into a stream that encapsulates a socket
 * @param resource|Socket $socket
 * @return resource|Socket|false
 */
function socket_export_stream(Socket $socket) {}

/**
 * Opens a socket on port to accept connections
 * @param int $port The port on which to listen on all interfaces.
 * @param int $backlog [optional] The backlog parameter defines the maximum length the queue of pending connections may grow to. SOMAXCONN may be passed as backlog parameter, see socket_listen for more information.
 * @return resource|Socket|false socket_create_listen returns a new socket resource on success or FALSE on error. The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_create_listen(int $port, int $backlog = 128): Socket|false {}

/**
 * Creates a pair of indistinguishable sockets and stores them in an array
 * @param int $domain The domain parameter specifies the protocol family to be used by the socket. See socket_create for the full list.
 * @param int $type The type parameter selects the type of communication to be used by the socket. See socket_create for the full list.
 * @param int $protocol The protocol parameter sets the specific protocol within the specified domain to be used when communicating on the returned socket. The proper value can be retrieved by name by using getprotobyname. If the desired protocol is TCP, or UDP the corresponding constants SOL_TCP, and ...
 * @param array &$pair Reference to an array in which the two socket resources will be inserted.
 * @return bool TRUE on success or FALSE on failure.
 */
function socket_create_pair(int $domain, int $type, int $protocol, &$pair): bool {}

/**
 * Accepts a connection on a socket
 * @param resource|Socket $socket A valid socket resource created with socket_create.
 * @return resource|Socket|false a new socket resource on success, or FALSE on error. The actual error code can be retrieved by calling socket_last_error. This error code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_accept(Socket $socket): Socket|false {}

/**
 * Sets nonblocking mode for file descriptor fd
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @return bool TRUE on success or FALSE on failure.
 */
function socket_set_nonblock(Socket $socket): bool {}

/**
 * Sets blocking mode on a socket resource
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @return bool TRUE on success or FALSE on failure.
 */
function socket_set_block(Socket $socket): bool {}

/**
 * Listens for a connection on a socket
 * @param resource|Socket $socket A valid socket resource created with socket_create.
 * @param int $backlog [optional] A maximum of backlog incoming connections will be queued for processing. If a connection request arrives with the queue full the client may receive an error with an indication of ECONNREFUSED, or, if the underlying protocol supports retransmission, the request may be ...
 * @return bool TRUE on success or FALSE on failure. The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_listen(Socket $socket, int $backlog = 0): bool {}

/**
 * Closes a socket resource
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @return void No value is returned.
 */
function socket_close(Socket $socket): void {}

/**
 * Write to a socket
 * @param resource|Socket $socket
 * @param string $data The buffer to be written.
 * @param int|null $length The optional parameter length can specify an alternate length of bytes written to the socket. If this length is greater than the buffer length, it is silently truncated to the length of the buffer.
 * @return int|false the number of bytes successfully written to the socket or FALSE on failure. The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual explanation of the error. It is perfectly valid for socket_write to return zero which ...
 */
function socket_write(Socket $socket, string $data, ?int $length = null): int|false {}

/**
 * Reads a maximum of length bytes from a socket
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param int $length The maximum number of bytes read is specified by the length parameter. Otherwise you can use \r, \n, or \0 to end reading (depending on the type parameter, see below).
 * @param int $mode [optional] Optional type parameter is a named constant: PHP_BINARY_READ (Default) - use the system recv() function. Safe for reading binary data.
 * @return string|false socket_read returns the data as a string on success, or FALSE on error (including if the remote host has closed the connection). The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual representation of the error. ...
 */
function socket_read(Socket $socket, int $length, int $mode = PHP_BINARY_READ): string|false {}

/**
 * Queries the local side of the given socket which may either result in host/port or in a Unix filesystem path, dependent on its type
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param string &$address If the given socket is of type AF_INET or AF_INET6, socket_getsockname will return the local IP address in appropriate notation (e.g. 127.0.0.1 or fe80::1) in the address parameter and, if the optional port parameter is present, also the associated port. If the given socket ...
 * @param int &$port [optional] If provided, this will hold the associated port.
 * @return bool TRUE on success or FALSE on failure. socket_getsockname may also return FALSE if the socket type is not any of AF_INET, AF_INET6, or AF_UNIX, in which case the last socket error code is not updated.
 */
function socket_getsockname(Socket $socket, &$address, &$port = null): bool {}

/**
 * Queries the remote side of the given socket which may either result in host/port or in a Unix filesystem path, dependent on its type
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param string &$address If the given socket is of type AF_INET or AF_INET6, socket_getpeername will return the peers (remote) IP address in appropriate notation (e.g. 127.0.0.1 or fe80::1) in the address parameter and, if the optional port parameter is present, also the associated port. If the ...
 * @param int &$port [optional] If given, this will hold the port associated to address.
 * @return bool TRUE on success or FALSE on failure. socket_getpeername may also return FALSE if the socket type is not any of AF_INET, AF_INET6, or AF_UNIX, in which case the last socket error code is not updated.
 */
function socket_getpeername(Socket $socket, &$address, &$port = null): bool {}

/**
 * Initiates a connection on a socket
 * @param resource|Socket $socket A Socket instance created with socket_create.
 * @param string $address The address parameter is either an IPv4 address in dotted-quad notation (e.g. 127.0.0.1) if socket is AF_INET, a valid IPv6 address (e.g. ::1) if IPv6 support is enabled and socket is AF_INET6 or the pathname of a Unix domain socket, if the socket family is AF_UNIX.
 * @param int|null $port The port parameter is only used and is mandatory when connecting to an AF_INET or an AF_INET6 socket, and designates the port on the remote host to which a connection should be made.
 * @return bool TRUE on success or FALSE on failure. The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual explanation of the error. If the socket is non-blocking then this function returns FALSE with an error Operation now in progress.
 */
function socket_connect(Socket $socket, string $address, ?int $port = null): bool {}

/**
 * Return a string describing a socket error
 * @param int $error_code A valid socket error number, likely produced by socket_last_error.
 * @return string the error message associated with the errno parameter.
 */
function socket_strerror(int $error_code): string {}

/**
 * Binds a name to a socket
 * @param resource|Socket $socket A valid socket resource created with socket_create.
 * @param string $address If the socket is of the AF_INET family, the address is an IP in dotted-quad notation (e.g. 127.0.0.1). If the socket is of the AF_UNIX family, the address is the path of a Unix-domain socket (e.g. /tmp/my.sock).
 * @param int $port [optional] The port parameter is only used when binding an AF_INET socket, and designates the port on which to listen for connections.
 * @return bool TRUE on success or FALSE on failure. The error code can be retrieved with socket_last_error. This code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_bind(Socket $socket, string $address, int $port = 0): bool {}

/**
 * Receives data from a connected socket
 * @param resource|Socket $socket The socket must be a socket resource previously created by socket_create().
 * @param string &$data The data received will be fetched to the variable specified with buf. If an error occurs, if the connection is reset, or if no data is available, buf will be set to NULL.
 * @param int $length Up to len bytes will be fetched from remote host.
 * @param int $flags The value of flags can be any combination of the following flags, joined with the binary OR (|) operator. Possible values for flags Flag Description MSG_OOB Process out-of-band data. MSG_PEEK Receive data from the beginning of the receive queue without removing it from the queue. ...
 * @return int|false socket_recv returns the number of bytes received, or FALSE if there was an error. The actual error code can be retrieved by calling socket_last_error. This error code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_recv(Socket $socket, &$data, int $length, int $flags): int|false {}

/**
 * Sends data to a connected socket
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param string $data A buffer containing the data that will be sent to the remote host.
 * @param int $length The number of bytes that will be sent to the remote host from buf.
 * @param int $flags The value of flags can be any combination of the following flags, joined with the binary OR (|) operator. Possible values for flags MSG_OOB Send OOB (out-of-band) data. MSG_EOR Indicate a record mark. The sent data completes the record. MSG_EOF Close the sender side of the socket ...
 * @return int|false socket_send returns the number of bytes sent, or FALSE on error.
 */
function socket_send(Socket $socket, string $data, int $length, int $flags): int|false {}

/**
 * Send a message
 * @param resource|Socket $socket
 * @param array $message
 * @param int $flags
 * @return int|false
 * @since 5.5
 */
function socket_sendmsg(
    Socket $socket,
    array $message,
    int $flags = 0
): int|false {}

/**
 * Receives data from a socket whether or not it is connection-oriented
 * @param resource|Socket $socket The socket must be a socket resource previously created by socket_create().
 * @param string &$data The data received will be fetched to the variable specified with buf.
 * @param int $length Up to len bytes will be fetched from remote host.
 * @param int $flags The value of flags can be any combination of the following flags, joined with the binary OR (|) operator. Possible values for flags Flag Description MSG_OOB Process out-of-band data. MSG_PEEK Receive data from the beginning of the receive queue without removing it from the queue. ...
 * @param string &$address If the socket is of the type AF_UNIX type, name is the path to the file. Else, for unconnected sockets, name is the IP address of, the remote host, or NULL if the socket is connection-oriented.
 * @param int &$port [optional] This argument only applies to AF_INET and AF_INET6 sockets, and specifies the remote port from which the data is received. If the socket is connection-oriented, port will be NULL.
 * @return int|false socket_recvfrom returns the number of bytes received, or FALSE if there was an error. The actual error code can be retrieved by calling socket_last_error. This error code may be passed to socket_strerror to get a textual explanation of the error.
 */
function socket_recvfrom(Socket $socket, &$data, int $length, int $flags, &$address, &$port = null): int|false {}

/**
 * Read a message
 * @param resource|Socket $socket
 * @param array &$message
 * @param int $flags
 * @return int|false
 * @since 5.5
 */
function socket_recvmsg(
    Socket $socket,
    array &$message,
    int $flags = 0
): int|false {}

/**
 * Sends a message to a socket, whether it is connected or not
 * @param resource|Socket $socket A valid socket resource created using socket_create.
 * @param string $data The sent data will be taken from buffer buf.
 * @param int $length len bytes from buf will be sent.
 * @param int $flags The value of flags can be any combination of the following flags, joined with the binary OR (|) operator. Possible values for flags MSG_OOB Send OOB (out-of-band) data. MSG_EOR Indicate a record mark. The sent data completes the record. MSG_EOF Close the sender side of the socket ...
 * @param string $address IP address of the remote host.
 * @param int|null $port port is the remote port number at which the data will be sent.
 * @return int|false socket_sendto returns the number of bytes sent to the remote host, or FALSE if an error occurred.
 */
function socket_sendto(Socket $socket, string $data, int $length, int $flags, string $address, ?int $port = null): int|false {}

/**
 * Gets socket options for the socket
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param int $level The level parameter specifies the protocol level at which the option resides. For example, to retrieve options at the socket level, a level parameter of SOL_SOCKET would be used. Other levels, such as TCP, can be used by specifying the protocol number of that level. Protocol ...
 * @param int $option Available Socket Options Option Description Type SO_DEBUG Reports whether debugging information is being recorded. int SO_BROADCAST Reports whether transmission of broadcast messages is supported. int SO_REUSEADDR Reports whether local addresses can be reused. int SO_KEEPALIVE ...
 * @return array|int|false the value of the given option, or FALSE on errors.
 */
function socket_get_option(Socket $socket, int $level, int $option): array|int|false {}

/**
 * Sets socket options for the socket
 * @param resource|Socket $socket A valid socket resource created with socket_create or socket_accept.
 * @param int $level The level parameter specifies the protocol level at which the option resides. For example, to retrieve options at the socket level, a level parameter of SOL_SOCKET would be used. Other levels, such as TCP, can be used by specifying the protocol number of that level. Protocol ...
 * @param int $option The available socket options are the same as those for the socket_get_option function.
 * @param mixed $value The option value.
 * @return bool TRUE on success or FALSE on failure.
 */
function socket_set_option(Socket $socket, int $level, int $option, $value): bool {}

/**
 * Shuts down a socket for receiving, sending, or both
 * @param resource|Socket $socket A valid socket resource created with socket_create.
 * @param int $mode [optional] The value of how can be one of the following: possible values for how 0 Shutdown socket reading 1 Shutdown socket writing 2 Shutdown socket reading and writing
 * @return bool TRUE on success or FALSE on failure.
 */
function socket_shutdown(Socket $socket, int $mode = 2): bool {}

/**
 * Returns the last error on the socket
 * @param resource|Socket $socket [optional] A valid socket resource created with socket_create.
 * @return int This function returns a socket error code.
 */
function socket_last_error(?Socket $socket = null): int {}

/**
 * Clears the error on the socket or the last error code
 * @param resource|Socket|null $socket [optional] A valid socket resource created with socket_create.
 * @return void No value is returned.
 */
function socket_clear_error(?Socket $socket = null): void {}

/**
 * Import a stream
 * @param resource|Socket $stream The stream resource to import.
 * @return resource|Socket|false|null FALSE or NULL on failure.
 * @since 5.4
 */
function socket_import_stream($stream): Socket|false {}

/**
 * Calculate message buffer size
 * @param int $level
 * @param int $type
 * @param int $num [optional]
 * @return int|null Since 8.6 always returns int.
 * @since 5.5
 */
function socket_cmsg_space(
    int $level,
    int $type,
    int $num = 0
): int|null {}

/**
 * Alias of socket_get_option
 * @param Socket $socket
 * @param int $level
 * @param int $option
 */
function socket_getopt(Socket $socket, int $level, int $option): array|int|false {}

/**
 * Alias of socket_set_option
 * @param Socket $socket
 * @param int $level
 * @param int $option
 * @param $value
 * @return bool
 */
function socket_setopt(Socket $socket, int $level, int $option, $value): bool {}

/**
 * Exports the WSAPROTOCOL_INFO Structure
 * @param resource|Socket $socket A Socket instance.
 * @param int $target_pid
 * @return string|false Returns an identifier to be used for the import, or false on failure
 * @since 7.3
 */
function socket_wsaprotocol_info_export($socket, $target_pid) {}

/**
 * Imports a Socket from another Process
 * @param string $info_id The ID which has been returned by a former call to socket_wsaprotocol_info_export.
 * @return resource|Socket|false Returns a Socket instance on success, or false on failure
 * @since 7.3
 */
function socket_wsaprotocol_info_import($info_id) {}

/**
 * Releases an exported WSAPROTOCOL_INFO Structure
 * @param string $info_id The ID which has been returned by a former call to socket_wsaprotocol_info_export.
 * @return bool Returns true on success or false on failure.
 * @since 7.3
 */
function socket_wsaprotocol_info_release($info_id) {}

/**
 * Determines whether socket is at out-of-band mark
 * @since 8.3
 */
function socket_atmark(Socket $socket): bool {}
