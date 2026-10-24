<?php

/**
 * Send a signal to a process
 * @param int $process_id The process identifier.
 * @param int $signal One of the PCNTL signals constants.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_kill(int $process_id, int $signal): bool {}

/**
 * Return the current process identifier
 * @return int the identifier, as an integer.
 */
function posix_getpid(): int {}

/**
 * Return the parent process identifier
 * @return int the identifier, as an integer.
 */
function posix_getppid(): int {}

/**
 * Return the real user ID of the current process
 * @return int the user id, as an integer
 */
function posix_getuid(): int {}

/**
 * Set the UID of the current process
 * @param int $user_id The user id.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_setuid(int $user_id): bool {}

/**
 * Return the effective user ID of the current process
 * @return int the user id, as an integer
 */
function posix_geteuid(): int {}

/**
 * Set the effective UID of the current process
 * @param int $user_id The user id.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_seteuid(int $user_id): bool {}

/**
 * Set system resource limits
 * @param int $resource The resource limit constant corresponding to the limit that is being set.
 * @param int $soft_limit The soft limit, in whatever unit the resource limit requires, or POSIX_RLIMIT_INFINITY.
 * @param int $hard_limit The hard limit, in whatever unit the resource limit requires, or POSIX_RLIMIT_INFINITY.
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 7.0
 */
function posix_setrlimit(int $resource, int $soft_limit, int $hard_limit): bool {}

/**
 * Return the real group ID of the current process
 * @return int the real group id, as an integer.
 */
function posix_getgid(): int {}

/**
 * Set the GID of the current process
 * @param int $group_id The group id.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_setgid(int $group_id): bool {}

/**
 * Return the effective group ID of the current process
 * @return int an integer of the effective group ID.
 */
function posix_getegid(): int {}

/**
 * Set the effective GID of the current process
 * @param int $group_id The group id.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_setegid(int $group_id): bool {}

/**
 * Return the group set of the current process
 * @return array|false an array of integers containing the numeric group ids of the group set of the current process.
 */
function posix_getgroups(): array|false {}

/**
 * Return login name
 * @return string|false the login name of the user, as a string.
 */
function posix_getlogin(): string|false {}

/**
 * Return the current process group identifier
 * @return int the identifier, as an integer.
 */
function posix_getpgrp(): int {}

/**
 * Make the current process a session leader
 * @return int the session id, or -1 on errors.
 */
function posix_setsid(): int {}

/**
 * Set process group id for job control
 * @param int $process_id The process id.
 * @param int $process_group_id The process group id.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_setpgid(int $process_id, int $process_group_id): bool {}

/**
 * Get process group id for job control
 * @param int $process_id The process id.
 * @return int|false the identifier, as an integer.
 */
function posix_getpgid(int $process_id): int|false {}

/**
 * Get the current sid of the process
 * @param int $process_id The process identifier. If set to 0, the current process is assumed. If an invalid pid is specified, then FALSE is returned and an error is set which can be checked with posix_get_last_error.
 * @return int|false the identifier, as an integer.
 */
function posix_getsid(int $process_id): int|false {}

/**
 * Get system name
 * @return array|false a hash of strings with information about the system. The indices of the hash are sysname - operating system name (e.g. Linux) nodename - system name (e.g. valiant) release - operating system release (e.g. 2.2.10) version - operating system version (e.g. #4 Tue Jul 20 17:01:36 ...
 */
function posix_uname(): array|false {}

/**
 * Get process times
 * @return array|false a hash of strings with information about the current process CPU usage. The indices of the hash are: ticks - the number of clock ticks that have elapsed since reboot. utime - user time used by the current process. stime - system time used by the current process. cutime - user ...
 */
function posix_times(): array|false {}

/**
 * Get path name of controlling terminal
 * @return string|false Upon successful completion, returns string of the pathname to the current controlling terminal. Otherwise FALSE is returned and errno is set, which can be checked with posix_get_last_error.
 */
function posix_ctermid(): string|false {}

/**
 * Determine terminal device name
 * @param resource|int $file_descriptor The file descriptor.
 * @return string|false On success, returns a string of the absolute path of the fd. On failure, returns FALSE
 */
function posix_ttyname($file_descriptor): string|false {}

/**
 * Determine if a file descriptor is an interactive terminal
 * @param resource|int $file_descriptor The file descriptor, which is expected to be either a file resource or an integer. An integer will be assumed to be a file descriptor that can be passed directly to the underlying system call. In almost all cases, you will want to provide a file resource.
 * @return bool TRUE if fd is an open descriptor connected to a terminal and FALSE otherwise.
 */
function posix_isatty($file_descriptor): bool {}

/**
 * Pathname of current directory
 * @return string|false a string of the absolute pathname on success. On error, returns FALSE and sets errno which can be checked with posix_get_last_error.
 */
function posix_getcwd(): string|false {}

/**
 * Create a fifo special file (a named pipe)
 * @param string $filename Path to the FIFO file.
 * @param int $permissions The second parameter mode has to be given in octal notation (e.g. 0644). The permission of the newly created FIFO also depends on the setting of the current umask. The permissions of the created file are (mode & ~umask).
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_mkfifo(string $filename, int $permissions): bool {}

/**
 * Create a special or ordinary file (POSIX.1)
 * @param string $filename The file to create
 * @param int $flags This parameter is constructed by a bitwise OR between file type (one of the following constants: POSIX_S_IFREG, POSIX_S_IFCHR, POSIX_S_IFBLK, POSIX_S_IFIFO or POSIX_S_IFSOCK) and permissions.
 * @param int $major [optional] The major device kernel identifier (required to pass when using S_IFCHR or S_IFBLK).
 * @param int $minor [optional] The minor device kernel identifier.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_mknod(string $filename, int $flags, int $major = 0, int $minor = 0): bool {}

/**
 * Determine accessibility of a file
 * @param string $filename The name of the file to be tested.
 * @param int $flags [optional] A mask consisting of one or more of POSIX_F_OK, POSIX_R_OK, POSIX_W_OK and POSIX_X_OK. POSIX_R_OK, POSIX_W_OK and POSIX_X_OK request checking whether the file exists and has read, write and execute permissions, respectively. POSIX_F_OK just requests checking for the ...
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_access(string $filename, int $flags = POSIX_F_OK): bool {}

/**
 * Return info about a group by name
 * @param string $name The name of the group
 * @return array|false The array elements returned are: The group information array Element Description name The name element contains the name of the group. This is a short, usually less than 16 character "handle" of the group, not the real, full name. This should be the same as the name parameter ...
 */
function posix_getgrnam(string $name): array|false {}

/**
 * Return info about a group by group id
 * @param int $group_id The group id.
 * @return array|false The array elements returned are: The group information array Element Description name The name element contains the name of the group. This is a short, usually less than 16 character "handle" of the group, not the real, full name. passwd The passwd element contains the group's ...
 */
function posix_getgrgid(int $group_id): array|false {}

/**
 * Return info about a user by username
 * @param string $username An alphanumeric username.
 * @return array|false On success an array with the following elements is returned, else FALSE is returned: The user information array Element Description name The name element contains the username of the user. This is a short, usually less than 16 character "handle" of the user, not the real, full ...
 */
function posix_getpwnam(string $username): array|false {}

/**
 * Return info about a user by user id
 * @param int $user_id The user identifier.
 * @return array|false an associative array with the following elements: The user information array Element Description name The name element contains the username of the user. This is a short, usually less than 16 character "handle" of the user, not the real, full name. passwd The passwd element ...
 */
function posix_getpwuid(int $user_id): array|false {}

/**
 * Return info about system resource limits
 * @return array|false an associative array of elements for each limit that is defined. Each limit has a soft and a hard limit. List of possible limits returned Limit name Limit description core The maximum size of the core file. When 0, not core files are created. When core files are larger than this ...
 */
function posix_getrlimit(?int $resource = null): array|false {}

/**
 * Retrieve the error number set by the last posix function that failed
 * @return int the errno (error number) set by the last posix function that failed. If no errors exist, 0 is returned.
 */
function posix_get_last_error(): int {}

/**
 * Alias of posix_get_last_error
 */
function posix_errno(): int {}

/**
 * Retrieve the system error message associated with the given errno
 * @param int $error_code A POSIX error number, returned by posix_get_last_error. If set to 0, then the string "Success" is returned.
 * @return string the error message, as a string.
 */
function posix_strerror(int $error_code): string {}

/**
 * Calculate the group access list
 * @param string $username The user to calculate the list for.
 * @param int $group_id Typically the group number from the password file.
 * @return bool TRUE on success or FALSE on failure.
 */
function posix_initgroups(string $username, int $group_id): bool {}

/**
 * Returns system runtime information.
 * @since 8.3
 */
function posix_sysconf(int $conf_id): int {}

/**
 * Determine accessibility of a file
 *
 * posix_eaccess checks the effective user's permission of a file
 * @since 8.3
 */
function posix_eaccess(string $filename, int $flags = 0): bool {}

/**
 * Returns the value of a configurable limit
 * @since 8.3
 * @param resource|int $file_descriptor The file descriptor, which is expected to be either a file resource or an int. An int will be assumed to be a file descriptor that can be passed directly to the underlying system call.
 * @param int $name The name of the configurable limit, one of the following. POSIX_PC_LINK_MAX, POSIX_PC_MAX_CANON, POSIX_PC_MAX_INPUT, POSIX_PC_NAME_MAX, POSIX_PC_PATH_MAX, POSIX_PC_PIPE_BUF, POSIX_PC_CHOWN_RESTRICTED, POSIX_PC_NO_TRUNC, POSIX_PC_ALLOC_SIZE_MIN, POSIX_PC_SYMLINK_MAX.
 * @throws \ValueError Throws a ValueError when resource is invalid.
 */
function posix_fpathconf($file_descriptor, int $name): int|false {}

/**
 * Returns the value of a configurable limit from name for a path
 * @since 8.3
 * @throws \ValueError Throws a ValueError when path is empty.
 */
function posix_pathconf(string $path, int $name): int|false {}
