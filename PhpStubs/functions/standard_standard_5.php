<?php

/**
 * Get the boolean value of a variable
 * @param mixed $value the scalar value being converted to a boolean.
 * @return bool The boolean value of var.
 * @since 5.5
 */
function boolval(mixed $value): bool {}

/**
 * Get the integer value of a variable
 * @param mixed $value The scalar value being converted to an integer
 * @param int $base [optional] The base for the conversion
 * @return int The integer value of var on success, or 0 on failure. Empty arrays and objects return 0, non-empty arrays and objects return 1. The maximum value depends on the system. 32 bit systems have a maximum signed integer range of -2147483648 to 2147483647. So for example on such a system, ...
 */
function intval(mixed $value, int $base = 10): int {}

/**
 * Get float value of a variable
 * @param mixed $value May be any scalar type. should not be used on objects, as doing so will emit an E_NOTICE level error and return 1.
 * @return float value of the given variable. Empty arrays return 0, non-empty arrays return 1.
 */
function floatval(mixed $value): float {}

/**
 * Alias:
 * floatval
 * Get float value of a variable
 * @param mixed $value May be any scalar type. should not be used on objects, as doing so will emit an E_NOTICE level error and return 1.
 * @return float value of the given variable. Empty arrays return 0, non-empty arrays return 1.
 */
function doubleval(mixed $value): float {}

/**
 * Get string value of a variable
 * @param mixed $value The variable that is being converted to a string. $var may be any scalar type or an object that implements the __toString() method. You cannot use strval() on arrays or objects that do not implement the __toString() method.
 * @return string The string value of var.
 */
function strval(mixed $value): string {}

/**
 * Get the type of a variable
 * @param mixed $value The variable being type checked.
 * @return string Possibles values for the returned string are: "boolean" "integer" "double" (for historical reasons "double" is returned in case of a float, and not simply "float") "string" "array" "object" "resource" "NULL" "unknown type" "resource (closed)" since 7.2.0
 */
function gettype(mixed $value): string {}

/**
 * Set the type of a variable
 * @param mixed &$var The variable being converted.
 * @param string $type Possibles values of type are: "boolean" (or, since PHP 4.2.0, "bool") "integer" (or, since PHP 4.2.0, "int") "float" (only possible since PHP 4.2.0, for older versions use the deprecated variant "double") "string" "array" "object" "null" (since PHP 4.2.0)
 * @return bool true on success or false on failure.
 * @throws \ValueError Throws a ValueError if the value of type is not a valid type, as of PHP 8.0.0. Prior to PHP 8.0.0, a E_WARNING was emitted and false was returned.
 */
function settype(mixed &$var, string $type): bool {}

/**
 * Finds whether a variable is null.
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is null, false otherwise.
 */
function is_null(mixed $value): bool {}

/**
 * Finds whether a variable is a resource
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a resource, false otherwise.
 */
function is_resource(mixed $value): bool {}

/**
 * Finds out whether a variable is a boolean
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a boolean, false otherwise.
 */
function is_bool(mixed $value): bool {}

/**
 * Alias:
 * is_int
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is an integer, false otherwise.
 */
function is_long(mixed $value): bool {}

/**
 * Finds whether the type of a variable is float
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a float, false otherwise.
 */
function is_float(mixed $value): bool {}

/**
 * Find whether the type of a variable is integer
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is an integer, false otherwise.
 */
function is_int(mixed $value): bool {}

/**
 * Alias:
 * is_int
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is an integer, false otherwise.
 */
function is_integer(mixed $value): bool {}

/**
 * Alias:
 * is_float
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a float, false otherwise.
 */
function is_double(mixed $value): bool {}

/**
 * Alias:
 * is_float
 * @param mixed $var The variable being evaluated.
 * @return bool true if var is a float, false otherwise.
 * @deprecated
 */
function is_real(mixed $var): bool {}

/**
 * Finds whether a variable is a number or a numeric string
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a number or a numeric string, false otherwise.
 */
function is_numeric(mixed $value): bool {}

/**
 * Find whether the type of a variable is string
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is of type string, false otherwise.
 */
function is_string(mixed $value): bool {}

/**
 * Finds whether a variable is an array
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is an array, false otherwise.
 */
function is_array(mixed $value): bool {}

/**
 * Finds whether a variable is an object
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is an object, false otherwise. Since 7.2.0 returns true for unserialized objects without a class definition (class of __PHP_Incomplete_Class).
 */
function is_object(mixed $value): bool {}

/**
 * Finds whether a variable is a scalar
 * @param mixed $value The variable being evaluated.
 * @return bool true if var is a scalar false otherwise.
 */
function is_scalar(mixed $value): bool {}

/**
 * Verify that the contents of a variable can be called as a function
 * @param callable|mixed $value The value to check
 * @param bool $syntax_only [optional] If set to TRUE the function only verifies that name might be a function or method. It will only reject simple variables that are not strings, or an array that does not have a valid structure to be used as a callback. The valid ones are supposed to have only 2 ...
 * @param string &$callable_name [optional] Receives the "callable name". In the example below it is "someClass::someMethod". Note, however, that despite the implication that someClass::SomeMethod() is a callable static method, this is not the case.
 * @return bool TRUE if $var is callable, FALSE otherwise.
 */
function is_callable(mixed $value, bool $syntax_only = false, &$callable_name = null): bool {}

/**
 * Verify that the contents of a variable is a countable value
 * @param mixed $value The value to check
 * @return bool TRUE if $var is countable, FALSE otherwise.
 * @since 7.3
 */
function is_countable(mixed $value): bool {}

/**
 * Closes process file pointer
 * @param resource $handle The file pointer must be valid, and must have been returned by a successful call to popen.
 * @return int the termination status of the process that was run. In case of an error then -1 is returned. If PHP has been compiled with --enable-sigchild, the return value of this function is undefined.
 */
function pclose($handle): int {}

/**
 * Opens process file pointer
 * @param string $command The command
 * @param string $mode The mode
 * @return resource|false a file pointer identical to that returned by fopen, except that it is unidirectional (may only be used for reading or writing) and must be closed with pclose. This pointer may be used with fgets, fgetss, and fwrite. If an error occurs, returns false.
 */
function popen(string $command, string $mode) {}

/**
 * Outputs a file
 * @param string $filename The filename being read.
 * @param bool $use_include_path [optional] You can use the optional second parameter and set it to true, if you want to search for the file in the include_path, too.
 * @param resource $context [optional] A context stream resource.
 * @return false|int the number of bytes read from the file, or FALSE on failure
 */
function readfile(string $filename, bool $use_include_path = false, $context = null): int|false {}

/**
 * Rewind the position of a file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen.
 * @return bool true on success or false on failure.
 */
function rewind($stream): bool {}

/**
 * Removes directory
 * @param string $directory Path to the directory.
 * @param resource $context [optional]
 * @return bool true on success or false on failure.
 */
function rmdir(string $directory, $context = null): bool {}

/**
 * Changes the current umask
 * @param int|null $mask [optional] The new umask.
 * @return int umask without arguments simply returns the current umask otherwise the old umask is returned.
 */
function umask(?int $mask = null): int {}

/**
 * Closes an open file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen or fsockopen.
 * @return bool true on success or false on failure.
 */
function fclose($stream): bool {}

/**
 * Tests for end-of-file on a file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @return bool true if the file pointer is at EOF or an error occurs (including socket timeout); otherwise returns false.
 */
function feof($stream): bool {}

/**
 * Gets character from file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @return string|false a string containing a single character read from the file pointed to by handle. Returns false on EOF.
 */
function fgetc($stream): string|false {}

/**
 * Gets line from file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @param int|null $length [optional] Reading ends when length - 1 bytes have been read, on a newline (which is included in the return value), or on EOF (whichever comes first). If no length is specified, it will keep reading from the stream until it reaches the end of the line. Until PHP 4.3.0, ...
 * @return string|false a string of up to length - 1 bytes read from the file pointed to by handle. If an error occurs, returns false.
 */
function fgets($stream, ?int $length = null): string|false {}

/**
 * Gets line from file pointer and strip HTML tags
 * @param resource $handle The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @param null|int $length [optional] Length of the data to be retrieved.
 * @param string $allowable_tags [optional] You can use the optional third parameter to specify tags which should not be stripped.
 * @return string|false a string of up to length - 1 bytes read from the file pointed to by handle, with all HTML and PHP code stripped. If an error occurs, returns false.
 * @removed 8.0
 * @deprecated
 */
function fgetss($handle, ?int $length = null, $allowable_tags = null): false|string {}

/**
 * Binary-safe file read
 * @param resource $stream &fs.file.pointer;
 * @param int $length Up to length number of bytes read.
 * @return string|false the read string or false on failure.
 */
function fread($stream, int $length): string|false {}

/**
 * Opens file or URL
 * @param string $filename If filename is of the form "scheme://...", it is assumed to be a URL and PHP will search for a protocol handler (also known as a wrapper) for that scheme. If no wrappers for that protocol are registered, PHP will emit a notice to help you track potential problems in your ...
 * @param string $mode The mode parameter specifies the type of access you require to the stream. It may be any of the following: A list of possible modes for fopen using mode mode Description 'r' Open for reading only; place the file pointer at the beginning of the file. 'r+' Open for reading and ...
 * @param bool $use_include_path [optional] The optional third use_include_path parameter can be set to '1' or true if you want to search for the file in the include_path, too.
 * @param resource $context [optional]
 * @return resource|false a file pointer resource on success, or false on error.
 */
function fopen(string $filename, string $mode, bool $use_include_path = false, $context = null) {}

/**
 * Output all remaining data on a file pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @return int|false If an error occurs, fpassthru returns false. Otherwise, fpassthru returns the number of characters read from handle and passed through to the output.
 */
function fpassthru($stream): int {}

/**
 * Truncates a file to a given length
 * @param resource $stream The file pointer. The handle must be open for writing.
 * @param int $size The size to truncate to. If size is larger than the file it is extended with null bytes. If size is smaller than the extra data will be lost.
 * @return bool true on success or false on failure.
 */
function ftruncate($stream, int $size): bool {}

/**
 * Gets information about a file using an open file pointer
 * @param resource $stream &fs.file.pointer;
 * @return array|false an array with the statistics of the file; the format of the array is described in detail on the stat manual page.
 */
function fstat($stream): array|false {}

/**
 * Seeks on a file pointer
 * @param resource $stream &fs.file.pointer;
 * @param int $offset The offset. To move to a position before the end-of-file, you need to pass a negative value in offset and set whence to SEEK_END.
 * @param int $whence [optional] whence values are: SEEK_SET - Set position equal to offset bytes. SEEK_CUR - Set position to current location plus offset. SEEK_END - Set position to end-of-file plus offset. If whence is not specified, it is assumed to be SEEK_SET.
 * @return int Upon success, returns 0; otherwise, returns -1. Note that seeking past EOF is not considered an error.
 */
function fseek($stream, int $offset, int $whence = SEEK_SET): int {}

/**
 * Returns the current position of the file read/write pointer
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen or popen. ftell gives undefined results for append-only streams (opened with "a" flag).
 * @return int|false the position of the file pointer referenced by handle as an integer; i.e., its offset into the file stream. If an error occurs, returns false.
 */
function ftell($stream): int|false {}

/**
 * Flushes the output to a file
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen() or fsockopen() (and not yet closed by fclose()).
 * @return bool true on success or false on failure.
 */
function fflush($stream): bool {}

/**
 * Sync file to storage. Similar to fflush() but blocks until OS buffers have flushed.
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen or fsockopen (and not yet closed by fclose).
 * @since 8.1
 */
function fsync($stream): bool {}

/**
 * Sync file data only to storage. Similar to fsync but does not flush modified metadata. POSIX only, aliased to fsync on Win32.
 * @param resource $stream The file pointer must be valid, and must point to a file successfully opened by fopen or fsockopen (and not yet closed by fclose).
 * @since 8.1
 */
function fdatasync($stream): bool {}

/**
 * Binary-safe file write
 * @param resource $stream &fs.file.pointer;
 * @param string $data The string that is to be written.
 * @param int|null $length [optional] If the length argument is given, writing will stop after length bytes have been written or the end of string is reached, whichever comes first. Note that if the length argument is given, then the magic_quotes_runtime configuration option will be ignored and no ...
 * @return int|false the number of bytes written, or FALSE on error.
 */
function fwrite($stream, string $data, ?int $length = null): int|false {}

/**
 * Alias:
 * fwrite
 * @param resource $stream A file system pointer resource that is typically created using fopen().
 * @param string $data The string that is to be written.
 * @param int|null $length [optional] If the length argument is given, writing will stop after length bytes have been written or the end of string is reached, whichever comes first. Note that if the length argument is given, then the magic_quotes_runtime configuration option will be ignored and no ...
 * @return int|false the number of bytes written, or FALSE on error.
 * @see fwrite()
 */
function fputs($stream, string $data, ?int $length = null): int|false {}

/**
 * Attempts to create the directory specified by pathname.
 * @param string $directory The directory path.
 * @param int $permissions [optional] The mode is 0777 by default, which means the widest possible access. For more information on modes, read the details on the chmod page. mode is ignored on Windows. Note that you probably want to specify the mode as an octal number, which means it should have a ...
 * @param bool $recursive [optional] Allows the creation of nested directories specified in the pathname. Default to false.
 * @param resource $context [optional]
 * @return bool true on success or false on failure.
 */
function mkdir(string $directory, int $permissions = 0777, bool $recursive = false, $context = null): bool {}

/**
 * Renames a file or directory
 * @param string $from The old name. The wrapper used in oldname must match the wrapper used in newname.
 * @param string $to The new name.
 * @param resource $context [optional]
 * @return bool true on success or false on failure.
 */
function rename(string $from, string $to, $context = null): bool {}

/**
 * Copies file
 * @param string $from Path to the source file.
 * @param string $to The destination path. If dest is a URL, the copy operation may fail if the wrapper does not support overwriting of existing files. If the destination file already exists, it will be overwritten.
 * @param resource $context [optional] A valid context resource created with stream_context_create.
 * @return bool true on success or false on failure.
 */
function copy(string $from, string $to, $context = null): bool {}

/**
 * Create file with unique file name
 * @param string $directory The directory where the temporary filename will be created.
 * @param string $prefix The prefix of the generated temporary filename. Windows use only the first three characters of prefix.
 * @return string|false the new temporary filename, or false on failure.
 */
function tempnam(string $directory, string $prefix): string|false {}

/**
 * Creates a temporary file
 * @return resource|false a file handle, similar to the one returned by fopen, for the new file or false on failure.
 */
function tmpfile() {}

/**
 * Reads entire file into an array
 * @param string $filename Path to the file.
 * @param int $flags The optional parameter flags can be one, or more, of the following constants: FILE_USE_INCLUDE_PATH - Search for the file in the include_path. FILE_IGNORE_NEW_LINES - Omit newline at the end of each array element FILE_SKIP_EMPTY_LINES - Skip empty lines
 * @param resource $context [optional] A context resource created with the stream_context_create function.
 * @return array|false the file in an array. Each element of the array corresponds to a line in the file, with the newline still attached. Upon failure, file returns false. Each line in the resulting array will include the line ending, unless FILE_IGNORE_NEW_LINES is used, so you still need to use ...
 * @throws \ValueError As of PHP 8.3.0, throws a ValueError if flags includes any invalid values, such as FILE_APPEND. Emits an E_WARNING level error if the file does not exist.
 */
function file(string $filename, int $flags = 0, $context = null): array|false {}

/**
 * Reads entire file into a string
 * @param string $filename Name of the file to read.
 * @param bool $use_include_path [optional] Note: As of PHP 5 the FILE_USE_INCLUDE_PATH constant can be used to trigger include path search.
 * @param resource $context [optional] A valid context resource created with stream_context_create. If you don't need to use a custom context, you can skip this parameter by null.
 * @param int $offset [optional] The offset where the reading starts.
 * @param int|null $length [optional] Maximum length of data read. The default is to read until end of file is reached.
 * @return string|false The function returns the read data or false on failure.
 */
function file_get_contents(string $filename, bool $use_include_path = false, $context = null, int $offset = 0, ?int $length = null): string|false {}

/**
 * Write a string to a file
 * @param string $filename Path to the file where to write the data.
 * @param mixed $data The data to write. Can be either a string, an array or a stream resource. If data is a stream resource, the remaining buffer of that stream will be copied to the specified file. This is similar with using stream_copy_to_stream. You can also specify the data parameter as a single ...
 * @param int $flags [optional] The value of flags can be any combination of the following flags (with some restrictions), joined with the binary OR (|) operator. Available flags Flag Description FILE_USE_INCLUDE_PATH Search for filename in the include directory. See include_path for more information. ...
 * @param resource $context [optional] A valid context resource created with stream_context_create.
 * @return int|false The function returns the number of bytes that were written to the file, or false on failure.
 */
function file_put_contents(string $filename, mixed $data, int $flags = 0, $context = null): int|false {}
