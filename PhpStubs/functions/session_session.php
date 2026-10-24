<?php

/**
 * Get and/or set the current session name.
 *
 * Before 7.2.0 checked cookie status and since 7.2.0 checks both cookie and session status to avoid PHP crash.
 * @param string|null $name [optional] The session name references the name of the session, which is used in cookies and URLs (e.g. PHPSESSID). It should contain only alphanumeric characters; it should be short and descriptive (i.e. for users with enabled cookie warnings). If name is specified, the ...
 * @return string|false the name of the current session.
 */
function session_name(null|string $name = null): string|false {}

/**
 * Get and/or set the current session module.
 *
 * Since 7.2.0 it is forbidden to set the module name to "user".
 * @param string|null $module [optional] If module is specified, that module will be used instead.
 * @return string|false the name of the current session module.
 */
function session_module_name(null|string $module = null): string|false {}

/**
 * Get and/or set the current session save path
 * @param string|null $path [optional] Session data path. If specified, the path to which data is saved will be changed. session_save_path needs to be called before session_start for that purpose. On some operating systems, you may want to specify a path on a filesystem that handles lots of small ...
 * @return string|false the path of the current directory used for data storage.
 */
function session_save_path(null|string $path = null): string|false {}

/**
 * Get and/or set the current session id
 * @param string|null $id [optional] If id is specified, it will replace the current session id. session_id needs to be called before session_start for that purpose. Depending on the session handler, not all characters are allowed within the session id. For example, the file session handler only ...
 * @return string|false session_id returns the session id for the current session or the empty string ("") if there is no current session (no current session id exists).
 */
function session_id(null|string $id = null): string|false {}

/**
 * Update the current session id with a newly generated one
 * @param bool $delete_old_session [optional] Whether to delete the old associated session file or not.
 * @return bool true on success or false on failure.
 */
function session_regenerate_id(bool $delete_old_session = false): bool {}

/**
 * PHP > 5.4.0
 *
 * Session shutdown function
 * @return void No value is returned.
 */
function session_register_shutdown(): void {}

/**
 * Decodes session data from a string
 * @param string $data The encoded data to be stored.
 * @return bool true on success or false on failure.
 */
function session_decode(string $data): bool {}

/**
 * Register one or more global variables with the current session
 * @param mixed $name A string holding the name of a variable or an array consisting of variable names or other arrays.
 * @param mixed ...$_ [optional]
 * @return bool true on success or false on failure.
 * @removed 5.4
 * @deprecated
 */
function session_register(mixed $name, ...$_): bool {}

/**
 * Unregister a global variable from the current session
 * @param string $name The variable name.
 * @return bool true on success or false on failure.
 * @removed 5.4
 * @deprecated
 */
function session_unregister(string $name): bool {}

/**
 * Find out whether a global variable is registered in a session
 * @param string $name The variable name.
 * @return bool session_is_registered returns true if there is a global variable with the name name registered in the current session, false otherwise.
 * @removed 5.4
 * @deprecated
 */
function session_is_registered(string $name): bool {}

/**
 * Encodes the current session data as a string
 * @return string|false the contents of the current session encoded.
 */
function session_encode(): string|false {}

/**
 * Initialize session data
 * @param array $options [optional] If provided, this is an associative array of options that will override the currently set session configuration directives. The keys should not include the session. prefix. In addition to the normal set of configuration directives, a read_and_close option may also ...
 * @return bool This function returns true if a session was successfully started, otherwise false.
 */
function session_start(array $options = []): bool {}

/**
 * Create new session id
 * @param string $prefix [optional] If prefix is specified, new session id is prefixed by prefix. Not all characters are allowed within the session id. Characters in the range a-z A-Z 0-9 , (comma) and - (minus) are allowed.
 * @return string|false new collision free session id for the current session. If it is used without active session, it omits collision check.
 * @since 7.1
 */
function session_create_id(string $prefix = ''): string|false {}

/**
 * Perform session data garbage collection
 * @return int|false number of deleted session data for success, false for failure.
 * @since 7.1
 */
function session_gc(): int|false {}

/**
 * Destroys all data registered to a session
 * @return bool true on success or false on failure.
 */
function session_destroy(): bool {}

/**
 * Free all session variables
 * @return void|bool since 7.2.0 returns true on success or false on failure.
 */
function session_unset(): bool {}

/**
 * Sets user-level session storage functions
 * @param callable $open Open function, this works like a constructor in classes and is executed when the session is being opened. The open function expects two parameters, where the first is the save path and the second is the session name.
 * @param callable $close Close function, this works like a destructor in classes and is executed when the session operation is done.
 * @param callable $read Read function must return string value always to make save handler work as expected. Return empty string if there is no data to read. Return values from other handlers are converted to boolean expression. true for success, false for failure.
 * @param callable $write Write function that is called when session data is to be saved. This function expects two parameters: an identifier and the data associated with it. The "write" handler is not executed until after the output stream is closed. Thus, output from debugging statements in the ...
 * @param callable $destroy The destroy handler, this is executed when a session is destroyed with session_destroy and takes the session id as its only parameter.
 * @param callable $gc The garbage collector, this is executed when the session garbage collector is executed and takes the max session lifetime as its only parameter.
 * @param callable|null $create_sid [optional] This callback is executed when a new session ID is required. No parameters are provided, and the return value should be a string that is a valid session ID for your handler.
 * @param callable|null $validate_sid [optional]
 * @param callable|null $update_timestamp [optional]
 * @return bool true on success or false on failure.
 */
function session_set_save_handler(callable $open, callable $close, callable $read, callable $write, callable $destroy, callable $gc, ?callable $create_sid = null, ?callable $validate_sid = null, ?callable $update_timestamp = null): bool {}

/**
 * Get and/or set the current cache limiter
 * @param string|null $value [optional] If cache_limiter is specified, the name of the current cache limiter is changed to the new value. Possible values Value Headers sent public Expires: (sometime in the future, according session.cache_expire) Cache-Control: public, max-age=(sometime in the future, ...
 * @return string|false the name of the current cache limiter.
 */
function session_cache_limiter(null|string $value = null): string|false {}

/**
 * Return current cache expire
 * @param int|null $value [optional] If new_cache_expire is given, the current cache expire is replaced with new_cache_expire. Setting new_cache_expire is of value only, if session.cache_limiter is set to a value different from nocache.
 * @return int|false the current setting of session.cache_expire. The value returned should be read in minutes, defaults to 180.
 */
function session_cache_expire(null|int $value = null): int|false {}

/**
 * Set the session cookie parameters
 * @param array $lifetime_or_options An associative array which may have any of the keys lifetime, path, domain, secure, httponly and samesite. The values have the same meaning as described for the parameters with the same name. The value of the samesite element should be either Lax or Strict. If any ...
 * @return bool returns true on success or false on failure.
 * @since 7.3
 */
function session_set_cookie_params(array $lifetime_or_options): bool {}

/**
 * Get the session cookie parameters
 * @return array an array with the current session cookie information, the array contains the following items: "lifetime" - The lifetime of the cookie in seconds. "path" - The path where information is stored. "domain" - The domain of the cookie. "secure" - The cookie should only be sent over secure ...
 */
function session_get_cookie_params(): array {}

/**
 * Write session data and end session
 * @return void|bool since 7.2.0 returns true on success or false on failure.
 */
function session_write_close(): bool {}

/**
 * Alias of session_write_close
 * @return void|bool since 7.2.0 returns true on success or false on failure.
 */
function session_commit(): bool {}

/**
 * Returns the current session status
 * @return int PHP_SESSION_DISABLED if sessions are disabled. PHP_SESSION_NONE if sessions are enabled, but none exists. PHP_SESSION_ACTIVE if sessions are enabled, and one exists.
 * @since 5.4
 */
function session_status(): int {}

/**
 * Discard session array changes and finish session
 * @return void|bool since 7.2.0 returns true if a session was successfully reinitialized or false on failure.
 * @since 5.6
 */
function session_abort(): bool {}

/**
 * Re-initialize session array with original values
 * @return void|bool since 7.2.0 returns true if a session was successfully reinitialized or false on failure.
 * @since 5.6
 */
function session_reset(): bool {}
