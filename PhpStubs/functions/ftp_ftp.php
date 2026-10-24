<?php

/**
 * append the contents of a file to another file on the ftp server
 * @param resource $ftp An FTP\Connection instance.
 * @param string $remote_filename
 * @param string $local_filename
 * @param int $mode Optional since PHP 7.3
 * @return bool
 * @since 7.2
 */
function ftp_append(
    \FTP\Connection $ftp,
    string $remote_filename,
    string $local_filename,
    int $mode = FTP_BINARY
): bool {}

/**
 * returns a list of files in the given directory
 * @param resource $ftp An FTP\Connection instance.
 * @param string $directory The directory to be listed.
 * @return array|false Returns an array of arrays with file infos from the specified directory on success or false on error.
 * @since 7.2
 */
function ftp_mlsd(\FTP\Connection $ftp, string $directory): array|false {}

/**
 * Opens an FTP connection
 * @param string $hostname The FTP server address. This parameter shouldn't have any trailing slashes and shouldn't be prefixed with ftp://.
 * @param int $port [optional] This parameter specifies an alternate port to connect to. If it is omitted or set to zero, then the default FTP port, 21, will be used.
 * @param int $timeout [optional] This parameter specifies the timeout for all subsequent network operations. If omitted, the default value is 90 seconds. The timeout can be changed and queried at any time with ftp_set_option and ftp_get_option.
 * @return resource|false a FTP stream on success or FALSE on error.
 */
function ftp_connect(string $hostname, int $port = 21, int $timeout = 90): \FTP\Connection|false {}

/**
 * Opens a Secure SSL-FTP connection
 * @param string $hostname The FTP server address. This parameter shouldn't have any trailing slashes and shouldn't be prefixed with ftp://.
 * @param int $port [optional] This parameter specifies an alternate port to connect to. If it is omitted or set to zero, then the default FTP port, 21, will be used.
 * @param int $timeout [optional] This parameter specifies the timeout for all subsequent network operations. If omitted, the default value is 90 seconds. The timeout can be changed and queried at any time with ftp_set_option and ftp_get_option.
 * @return resource|false a SSL-FTP stream on success or FALSE on error.
 */
function ftp_ssl_connect(string $hostname, int $port = 21, int $timeout = 90): \FTP\Connection|false {}

/**
 * Logs in to an FTP connection
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $username The username (USER).
 * @param string $password The password (PASS).
 * @return bool TRUE on success or FALSE on failure. If login fails, PHP will also throw a warning.
 */
function ftp_login(\FTP\Connection $ftp, string $username, string $password): bool {}

/**
 * Returns the current directory name
 * @param resource $ftp The link identifier of the FTP connection.
 * @return string|false the current directory name or FALSE on error.
 */
function ftp_pwd(\FTP\Connection $ftp): string|false {}

/**
 * Changes to the parent directory
 * @param resource $ftp The link identifier of the FTP connection.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_cdup(\FTP\Connection $ftp): bool {}

/**
 * Changes the current directory on a FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $directory The target directory.
 * @return bool TRUE on success or FALSE on failure. If changing directory fails, PHP will also throw a warning.
 */
function ftp_chdir(\FTP\Connection $ftp, string $directory): bool {}

/**
 * Requests execution of a command on the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $command The command to execute.
 * @return bool TRUE if the command was successful (server sent response code: 200); otherwise returns FALSE.
 */
function ftp_exec(\FTP\Connection $ftp, string $command): bool {}

/**
 * Sends an arbitrary command to an FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $command The command to execute.
 * @return string[] the server's response as an array of strings. No parsing is performed on the response string, nor does ftp_raw determine if the command succeeded.
 */
function ftp_raw(\FTP\Connection $ftp, string $command): array|null {}

/**
 * Creates a directory
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $directory The name of the directory that will be created.
 * @return string|false the newly created directory name on success or FALSE on error.
 */
function ftp_mkdir(\FTP\Connection $ftp, string $directory): string|false {}

/**
 * Removes a directory
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $directory The directory to delete. This must be either an absolute or relative path to an empty directory.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_rmdir(\FTP\Connection $ftp, string $directory): bool {}

/**
 * Set permissions on a file via FTP
 * @param resource $ftp The link identifier of the FTP connection.
 * @param int $permissions The new permissions, given as an octal value.
 * @param string $filename The remote file.
 * @return int|false the new file permissions on success or FALSE on error.
 */
function ftp_chmod(\FTP\Connection $ftp, int $permissions, string $filename): int|false {}

/**
 * Allocates space for a file to be uploaded
 * @param resource $ftp The link identifier of the FTP connection.
 * @param int $size The number of bytes to allocate.
 * @param string &$response [optional] A textual representation of the servers response will be returned by reference in result if a variable is provided.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_alloc(\FTP\Connection $ftp, int $size, &$response = null): bool {}

/**
 * Returns a list of files in the given directory
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $directory The directory to be listed. This parameter can also include arguments, eg. ftp_nlist($conn_id, "-la /your/dir"); Note that this parameter isn't escaped so there may be some issues with filenames containing spaces and other characters.
 * @return string[]|false an array of filenames from the specified directory on success or FALSE on error.
 */
function ftp_nlist(\FTP\Connection $ftp, string $directory): array|false {}

/**
 * Returns a detailed list of files in the given directory
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $directory The directory path. May include arguments for the LIST command.
 * @param bool $recursive [optional] If set to TRUE, the issued command will be LIST -R.
 * @return string[]|false an array where each element corresponds to one line of text. The output is not parsed in any way. The system type identifier returned by ftp_systype can be used to determine how the results should be interpreted.
 */
function ftp_rawlist(\FTP\Connection $ftp, string $directory, bool $recursive = false): array|false {}

/**
 * Returns the system type identifier of the remote FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @return string|false the remote system type, or FALSE on error.
 */
function ftp_systype(\FTP\Connection $ftp): string|false {}

/**
 * Turns passive mode on or off
 * @param resource $ftp The link identifier of the FTP connection.
 * @param bool $enable If TRUE, the passive mode is turned on, else it's turned off.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_pasv(\FTP\Connection $ftp, bool $enable): bool {}

/**
 * Downloads a file from the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $local_filename The local file path (will be overwritten if the file already exists).
 * @param string $remote_filename The remote file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start downloading from.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_get(
    \FTP\Connection $ftp,
    string $local_filename,
    string $remote_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): bool {}

/**
 * Downloads a file from the FTP server and saves to an open file
 * @param resource $ftp The link identifier of the FTP connection.
 * @param resource $stream An open file pointer in which we store the data.
 * @param string $remote_filename The remote file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Since PHP 7.3 parameter is optional
 * @param int $offset [optional] The position in the remote file to start downloading from.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_fget(
    \FTP\Connection $ftp,
    $stream,
    string $remote_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): bool {}

/**
 * Uploads a file to the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $remote_filename The remote file path.
 * @param string $local_filename The local file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start uploading to.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_put(
    \FTP\Connection $ftp,
    string $remote_filename,
    string $local_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): bool {}

/**
 * Uploads from an open file to the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $remote_filename The remote file path.
 * @param resource $stream An open file pointer on the local file. Reading stops at end of file.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start uploading to.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_fput(
    \FTP\Connection $ftp,
    string $remote_filename,
    $stream,
    int $mode = FTP_BINARY,
    int $offset = 0
): bool {}

/**
 * Returns the size of the given file
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $filename The remote file.
 * @return int the file size on success, or -1 on error.
 */
function ftp_size(\FTP\Connection $ftp, string $filename): int {}

/**
 * Returns the last modified time of the given file
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $filename The file from which to extract the last modification time.
 * @return int the last modified time as a Unix timestamp on success, or -1 on error.
 */
function ftp_mdtm(\FTP\Connection $ftp, string $filename): int {}

/**
 * Renames a file or a directory on the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $from The old file/directory name.
 * @param string $to The new name.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_rename(\FTP\Connection $ftp, string $from, string $to): bool {}

/**
 * Deletes a file on the FTP server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $filename The file to delete.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_delete(\FTP\Connection $ftp, string $filename): bool {}

/**
 * Sends a SITE command to the server
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $command The SITE command. Note that this parameter isn't escaped so there may be some issues with filenames containing spaces and other characters.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_site(\FTP\Connection $ftp, string $command): bool {}

/**
 * Closes an FTP connection
 * @param resource $ftp The link identifier of the FTP connection.
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_close(\FTP\Connection $ftp): bool {}

/**
 * Set miscellaneous runtime FTP options
 * @param resource $ftp The link identifier of the FTP connection.
 * @param int $option Currently, the following options are supported: Supported runtime FTP options FTP_TIMEOUT_SEC Changes the timeout in seconds used for all network related functions. value must be an integer that is greater than 0. The default timeout is 90 seconds. FTP_AUTOSEEK When enabled, GET ...
 * @param mixed $value This parameter depends on which option is chosen to be altered.
 * @return bool TRUE if the option could be set; FALSE if not. A warning message will be thrown if the option is not supported or the passed value doesn't match the expected value for the given option.
 * @throws \ValueError A ValueError is thrown if the option is not supported.
 * @throws \TypeError A TypeError is thrown if the passed value doesn't match the expected type for the given option.
 */
function ftp_set_option(\FTP\Connection $ftp, int $option, $value): bool {}

/**
 * Retrieves various runtime behaviours of the current FTP stream
 * @param resource $ftp The link identifier of the FTP connection.
 * @param int $option Currently, the following options are supported: Supported runtime FTP options FTP_TIMEOUT_SEC Returns the current timeout used for network related operations. FTP_AUTOSEEK Returns TRUE if this option is on, FALSE otherwise.
 * @return int|bool the value on success or FALSE if the given option is not supported. In the latter case, a warning message is also thrown.
 */
function ftp_get_option(\FTP\Connection $ftp, int $option): int|bool {}

/**
 * Retrieves a file from the FTP server and writes it to an open file (non-blocking)
 * @param resource $ftp The link identifier of the FTP connection.
 * @param resource $stream An open file pointer in which we store the data.
 * @param string $remote_filename The remote file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start downloading from.
 * @return int FTP_FAILED or FTP_FINISHED or FTP_MOREDATA.
 */
function ftp_nb_fget(
    \FTP\Connection $ftp,
    $stream,
    string $remote_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): int {}

/**
 * Retrieves a file from the FTP server and writes it to a local file (non-blocking)
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $local_filename The local file path (will be overwritten if the file already exists).
 * @param string $remote_filename The remote file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start downloading from.
 * @return int|false FTP_FAILED or FTP_FINISHED or FTP_MOREDATA.
 */
function ftp_nb_get(
    \FTP\Connection $ftp,
    string $local_filename,
    string $remote_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): int|false {}

/**
 * Continues retrieving/sending a file (non-blocking)
 * @param resource $ftp The link identifier of the FTP connection.
 * @return int FTP_FAILED or FTP_FINISHED or FTP_MOREDATA.
 */
function ftp_nb_continue(\FTP\Connection $ftp): int {}

/**
 * Stores a file on the FTP server (non-blocking)
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $remote_filename The remote file path.
 * @param string $local_filename The local file path.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start uploading to.
 * @return int|false FTP_FAILED or FTP_FINISHED or FTP_MOREDATA.
 */
function ftp_nb_put(
    \FTP\Connection $ftp,
    string $remote_filename,
    string $local_filename,
    int $mode = FTP_BINARY,
    int $offset = 0
): int|false {}

/**
 * Stores a file from an open file to the FTP server (non-blocking)
 * @param resource $ftp The link identifier of the FTP connection.
 * @param string $remote_filename The remote file path.
 * @param resource $stream An open file pointer on the local file. Reading stops at end of file.
 * @param int $mode The transfer mode. Must be either FTP_ASCII or FTP_BINARY. Optional since PHP 7.3
 * @param int $offset [optional] The position in the remote file to start uploading to.
 * @return int FTP_FAILED or FTP_FINISHED or FTP_MOREDATA.
 */
function ftp_nb_fput(
    \FTP\Connection $ftp,
    string $remote_filename,
    $stream,
    int $mode = FTP_BINARY,
    int $offset = 0
): int {}

/**
 * Alias of ftp_close
 * @param resource $ftp
 * @return bool TRUE on success or FALSE on failure.
 */
function ftp_quit(\FTP\Connection $ftp): bool {}
