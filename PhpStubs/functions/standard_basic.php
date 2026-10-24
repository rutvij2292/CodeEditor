<?php

/**
 * Loads a php extension at runtime
 * @param string $extension_filename This parameter is only the filename of the extension to load which also depends on your platform. For example, the sockets extension (if compiled as a shared module, not the default!) would be called sockets.so on Unix platforms whereas it is called php_sockets.dll ...
 * @return bool TRUE on success or FALSE on failure. If the functionality of loading modules is not available or has been disabled (either by setting enable_dl off or by enabling safe mode in php.ini) an E_ERROR is emitted and execution is stopped. If dl fails because the specified library couldn't be ...
 */
function dl(string $extension_filename): bool {}

/**
 * Sets the process title
 * @param string $title The new title.
 * @return bool TRUE on success or FALSE on failure.
 * @since 5.5
 */
function cli_set_process_title(string $title): bool {}

/**
 * Returns the current process title, as set by cli_set_process_title(). Note that this may not exactly match what is shown in ps or top, depending on your operating system.
 * @return string|null Return a string with the current process title or NULL on error.
 * @since 5.5
 */
function cli_get_process_title(): ?string {}

/**
 * Verify that the contents of a variable is accepted by the iterable pseudo-type, i.e. that it is an array or an object implementing Traversable
 * @param mixed $value The value to check
 * @return bool Returns true if value is iterable, false otherwise.
 * @since 7.1
 */
function is_iterable(mixed $value): bool {}

/**
 * Encodes an ISO-8859-1 string to UTF-8
 * @param string $string An ISO-8859-1 string.
 * @return string the UTF-8 translation of data.
 * @deprecated
 */
function utf8_encode(string $string): string {}

/**
 * Converts a string with ISO-8859-1 characters encoded with UTF-8
 * to single-byte ISO-8859-1
 * @param string $string An UTF-8 encoded string.
 * @return string the ISO-8859-1 translation of data.
 * @deprecated
 */
function utf8_decode(string $string): string {}

/**
 * Clear the most recent error
 * @return void Clears the most recent errors, making it unable to be retrieved with error_get_last.
 * @since 7.0
 */
function error_clear_last(): void {}

/**
 * Get process codepage
 * @param string $kind The kind of operating system codepage to get, either 'ansi' or 'oem'. Any other value refers to the current codepage of the process.
 * @return int If kind is 'ansi', the current ANSI code page of the operating system is returned. If kind is 'oem', the current OEM code page of the operating system is returned. Otherwise, the current codepage of the process is returned.
 * @since 7.1
 */
function sapi_windows_cp_get(string $kind = ""): int {}

/**
 * Set process codepage
 * @param int $codepage A codepage identifier.
 * @return bool Returns true on success or false on failure.
 * @since 7.1
 */
function sapi_windows_cp_set(int $codepage): bool {}

/**
 * Convert string from one codepage to another
 * @param int|string $in_codepage The codepage of the subject string. Either the codepage name or identifier.
 * @param int|string $out_codepage The codepage to convert the subject string to. Either the codepage name or identifier.
 * @param string $subject The string to convert.
 * @return string|null The subject string converted to out_codepage, or null on failure.
 * @since 7.1
 */
function sapi_windows_cp_conv(int|string $in_codepage, int|string $out_codepage, string $subject): ?string {}

/**
 * Indicates whether the codepage is utf-8 compatible
 * @return bool Returns whether the codepage of the current process is UTF-8 compatible.
 * @since 7.1
 */
function sapi_windows_cp_is_utf8(): bool {}

/**
 * Get or set VT100 support for the specified stream associated to an output buffer of a Windows console.
 *
 * At startup, PHP tries to enable the VT100 feature of the STDOUT/STDERR streams.
 * By the way, if those streams are redirected to a file, the VT100 features may not be enabled.
 *
 * If VT100 support is enabled, it is possible to use control sequences as they are known from the VT100 terminal.
 * They allow the modification of the terminal's output. On Windows these sequences are called Console Virtual Terminal Sequences.
 *
 * Warning This function uses the ENABLE_VIRTUAL_TERMINAL_PROCESSING flag implemented in the Windows 10 API, so the VT100 feature may not be available on older Windows versions.
 * @param resource $stream The stream on which the function will operate.
 * @param bool|null $enable If bool, the VT100 feature will be enabled (if true) or disabled (if false). If enable is null, the function returns true if the stream stream has VT100 control codes enabled, false otherwise. If enable is a bool, the function will try to enable or disable the VT100 ...
 * @return bool If enable is null: returns true if the VT100 feature is enabled, false otherwise. If enable is a bool: Returns true on success or false on failure.
 * @since 7.2
 */
function sapi_windows_vt100_support($stream, ?bool $enable = null): bool {}

/**
 * Set or remove a CTRL event handler, which allows Windows CLI processes to intercept or ignore CTRL+C and CTRL+BREAK events.
 * Note that in multithreaded environments, this is only possible when called from the main thread.
 * @param callable|null $handler A callback function to set or remove. If set, this function will be called whenever a CTRL+C or CTRL+BREAK event occurs. The function is supposed to have the following signature: handler(int $event): void event The CTRL event which has been received; either ...
 * @param bool $add If true, the handler is set. If false, the handler is removed.
 * @return bool TRUE on success or FALSE on failure.
 * @since 7.4
 */
function sapi_windows_set_ctrl_handler(?callable $handler, bool $add = true): bool {}

/**
 * Send a CTRL event to another process.
 * @param int $event The CTRL even to send; either PHP_WINDOWS_EVENT_CTRL_C or PHP_WINDOWS_EVENT_CTRL_BREAK.
 * @param int $pid [optional] The ID of the process to which to send the event to. If 0 is given, the event is sent to all processes of the process group.
 * @return bool TRUE on success or FALSE on failure.
 * @since 7.4
 */
function sapi_windows_generate_ctrl_event(int $event, int $pid = 0): bool {}
