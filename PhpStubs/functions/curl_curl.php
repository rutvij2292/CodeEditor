<?php

/**
 * Initialize a cURL session
 * @param string|null $url [optional] If provided, the CURLOPT_URL option will be set to its value. You can manually set this using the curl_setopt function.
 * @return resource|false|CurlHandle a cURL handle on success, false on errors.
 */
function curl_init(?string $url = null): CurlHandle|false {}

/**
 * Copy a cURL handle along with all of its preferences
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return CurlHandle|resource|false a new cURL handle.
 */
function curl_copy_handle(CurlHandle $handle): CurlHandle|false {}

/**
 * Gets cURL version information
 * @param int $age [optional] Removed since version PHP 8.0.
 * @return array|false an associative array with the following elements: Indice Value description version_number cURL 24 bit version number version cURL version number, as a string ssl_version_number OpenSSL 24 bit version number ssl_version OpenSSL version number, as a string libz_version zlib ...
 */
function curl_version(): array|false {}

/**
 * Set an option for a cURL transfer
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @param int $option The CURLOPT_XXX option to set.
 * @param mixed|callable $value The value to be set on option. value should be a bool for the following values of the option parameter: Option Set value to Notes CURLOPT_AUTOREFERER TRUE to automatically set the Referer: field in requests where it follows a Location: redirect. CURLOPT_BINARYTRANSFER ...
 * @ prefix can be disabled for safe passing of values beginning with @ by setting the CURLOPT_SAFE_UPLOAD option to TRUE. CURLOPT_PROXY The HTTP proxy to tunnel requests through. CURLOPT_PROXYUSERPWD A username and password formatted as "[username]:[password]" to use for the connection to the proxy. ...
 * @ prefix can be disabled for safe passing of values beginning with @ by setting the CURLOPT_SAFE_UPLOAD option to TRUE. CURLOPT_PROXY The HTTP proxy to tunnel requests through. CURLOPT_PROXYUSERPWD A username and password formatted as "[username]:[password]" to use for the connection to the proxy. ...
 * @return bool true on success or false on failure.
 */
function curl_setopt(CurlHandle $handle, int $option, mixed $value): bool {}

/**
 * Set multiple options for a cURL transfer
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @param array $options An array specifying which options to set and their values. The keys should be valid curl_setopt constants or their integer equivalents.
 * @return bool true if all options were successfully set. If an option could not be successfully set, false is immediately returned, ignoring any future options in the options array.
 * @since 5.1
 */
function curl_setopt_array(CurlHandle $handle, array $options): bool {}

/**
 * Close a cURL share handle
 * @param CurlShareHandle|resource $share_handle A cURL share handle returned by  curl_share_init()
 * @return void No value is returned.
 * @since 5.5
 */
function curl_share_close(CurlShareHandle $share_handle): void {}

/**
 * Initialize a cURL share handle
 * @return resource|CurlShareHandle Returns resource of type "cURL Share Handle".
 * @since 5.5
 */
function curl_share_init(): CurlShareHandle {}

/**
 * Set an option for a cURL share handle.
 * @param CurlShareHandle|resource $share_handle A cURL share handle returned by  curl_share_init().
 * @param int $option Option Description CURLSHOPT_SHARE Specifies a type of data that should be shared. CURLSHOPT_UNSHARE Specifies a type of data that will be no longer shared.
 * @param string $value Value Description CURL_LOCK_DATA_COOKIE Shares cookie data. CURL_LOCK_DATA_DNS Shares DNS cache. Note that when you use cURL multi handles, all handles added to the same multi handle will share DNS cache by default. CURL_LOCK_DATA_SSL_SESSION Shares SSL session IDs, reducing ...
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function curl_share_setopt(CurlShareHandle $share_handle, int $option, mixed $value): bool {}

/**
 * Return string describing the given error code
 * @param int $error_code One of the  cURL error codes constants.
 * @return string|null Returns error description or NULL for invalid error code.
 * @since 5.5
 */
function curl_strerror(int $error_code): ?string {}

/**
 * Decodes the given URL encoded string
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init().
 * @param string $string The URL encoded string to be decoded.
 * @return string|false Returns decoded string or FALSE on failure.
 * @since 5.5
 */
function curl_unescape(CurlHandle $handle, string $string): string|false {}

/**
 * Perform a cURL session
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return string|bool true on success or false on failure. However, if the CURLOPT_RETURNTRANSFER option is set, it will return the result on success, false on failure.
 */
function curl_exec(CurlHandle $handle): string|bool {}

/**
 * Get information regarding a specific transfer
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @param int|null $option [optional] This may be one of the following constants: CURLINFO_EFFECTIVE_URL - Last effective URL CURLINFO_HTTP_CODE - The last response code. As of cURL 7.10.8, this is a legacy alias of CURLINFO_RESPONSE_CODE CURLINFO_FILETIME - Remote time of the retrieved document, with ...
 * @return mixed If $option is given, returns its value as a string. Otherwise, returns an associative array with the following elements (which correspond to $option), or false on failure: url content_type http_code header_size request_size filetime ssl_verify_result redirect_count total_time ...
 */
function curl_getinfo(CurlHandle $handle, ?int $option = null): mixed {}

/**
 * Return a string containing the last error for the current session
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return string the error message or '' (the empty string) if no error occurred.
 */
function curl_error(CurlHandle $handle): string {}

/**
 * Return the last error number
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return int the error number or 0 (zero) if no error occurred.
 */
function curl_errno(CurlHandle $handle): int {}

/**
 * URL encodes the given string
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init().
 * @param string $string The string to be encoded.
 * @return string|false Returns escaped string or FALSE on failure.
 * @since 5.5
 */
function curl_escape(CurlHandle $handle, string $string): string|false {}

/**
 * Create a CURLFile object
 * @param string $filename  Path to the file which will be uploaded.
 * @param string|null $mime_type Mimetype of the file.
 * @param string|null $posted_filename Name of the file.
 * @return CURLFile Returns a CURLFile object.
 * @since 5.5
 */
function curl_file_create(string $filename, ?string $mime_type = null, ?string $posted_filename = null): CURLFile {}

/**
 * Close a cURL session
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return void No value is returned.
 */
function curl_close(CurlHandle $handle): void {}

/**
 * Returns a new cURL multi handle
 * @return resource|CurlMultiHandle a cURL multi handle resource or object depends on the php version
 */
function curl_multi_init(): CurlMultiHandle {}

/**
 * Add a normal cURL handle to a cURL multi handle
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return int 0 on success, or one of the CURLM_XXX errors code.
 */
function curl_multi_add_handle(CurlMultiHandle $multi_handle, CurlHandle $handle): int {}

/**
 * Remove a multi handle from a set of cURL handles
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return int|false On success, returns one of the CURLM_XXX error codes, false on failure.
 */
function curl_multi_remove_handle(CurlMultiHandle $multi_handle, CurlHandle $handle): int {}

/**
 * Wait for activity on any curl_multi connection
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param float $timeout [optional] Time, in seconds, to wait for a response.
 * @return int On success, returns the number of descriptors contained in, the descriptor sets. On failure, this function will return -1 on a select failure or timeout (from the underlying select system call).
 * @throws \ValueError Throws a ValueError if timeout is less than 0 or greater than PHP_INT_MAX.
 */
function curl_multi_select(CurlMultiHandle $multi_handle, float $timeout = 1.0): int {}

/**
 * Set an option for the cURL multi handle
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param int $option One of the CURLMOPT_* constants.
 * @param mixed $value The value to be set on option. value should be an int for the following values of the option parameter: Option Set value to CURLMOPT_PIPELINING Pass 1 to enable or 0 to disable. Enabling pipelining on a multi handle will make it attempt to perform HTTP Pipelining as far as ...
 * @return bool Returns TRUE on success or FALSE on failure.
 * @since 5.5
 */
function curl_multi_setopt(CurlMultiHandle $multi_handle, int $option, mixed $value): bool {}

/**
 * Return string describing error code
 * @param int $error_code One of the CURLM error codes constants.
 * @return string|null Returns error string for valid error code, NULL otherwise.
 * @since 5.5
 */
function curl_multi_strerror(int $error_code): ?string {}

/**
 * Pause and unpause a connection
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init().
 * @param int $flags One of CURLPAUSE_* constants.
 * @return int Returns an error code (CURLE_OK for no error).
 * @since 5.5
 */
function curl_pause(CurlHandle $handle, int $flags): int {}

/**
 * Reset all options of a libcurl session handle
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init().
 * @return void No value is returned.
 * @since 5.5
 */
function curl_reset(CurlHandle $handle): void {}

/**
 * Run the sub-connections of the current cURL handle
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param int &$still_running A reference to a flag to tell whether the operations are still running.
 * @return int A cURL code defined in the cURL Predefined Constants. This only returns errors regarding the whole multi stack. There might still have occurred problems on individual transfers even when this function returns CURLM_OK.
 */
function curl_multi_exec(
    CurlMultiHandle $multi_handle,
    &$still_running
): int {}

/**
 * Return the content of a cURL handle if CURLOPT_RETURNTRANSFER is set
 * @param CurlHandle|resource $handle A cURL handle returned by curl_init.
 * @return null|string Return the content of a cURL handle if CURLOPT_RETURNTRANSFER is set.
 */
function curl_multi_getcontent(CurlHandle $handle): ?string {}

/**
 * Get information about the current transfers
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @param int &$queued_messages [optional] Number of messages that are still in the queue
 * @return array|false On success, returns an associative array for the message, false on failure.
 */
function curl_multi_info_read(CurlMultiHandle $multi_handle, &$queued_messages = null): array|false {}

/**
 * Close a set of cURL handles
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @return void No value is returned.
 */
function curl_multi_close(CurlMultiHandle $multi_handle): void {}

/**
 * Return the last multi curl error number
 * @param CurlMultiHandle|resource $multi_handle A cURL multi handle returned by curl_multi_init.
 * @return int Return an integer containing the last multi curl error number.
 * @since 7.1
 */
function curl_multi_errno(CurlMultiHandle $multi_handle): int {}

/**
 * Return the last share curl error number
 * @param CurlShareHandle|resource $share_handle A cURL share handle returned by curl_share_init.
 * @return int Returns an integer containing the last share curl error number.
 * @since 7.1
 */
function curl_share_errno(CurlShareHandle $share_handle): int {}

/**
 * Return string describing the given error code
 * @param int $error_code One of the cURL error codes constants.
 * @return string|null Returns error description or null for invalid error code.
 * @since 7.1
 */
function curl_share_strerror(int $error_code): ?string {}

/**
 * Performs any connection upkeep checks
 *
 * Available if built against libcurl >= 7.62.0.
 * @since 8.2
 */
function curl_upkeep(CurlHandle $handle): bool {}

/**
 * @since 8.5
 */
function curl_multi_get_handles(CurlMultiHandle $multi_handle): array {}

/**
 * Initialize a persistent cURL share handle
 *
 * Initialize a persistent cURL share handle with the given share options. Unlike curl_share_init,
 * handles created by this function will not be destroyed at the end of the PHP request. If a
 * persistent share handle with the same set of share_options is found, it will be reused.
 * @since 8.5
 * @throws \ValueError If share_options is empty, this function throws a ValueError. If share_options contains a value not matching a CURL_LOCK_DATA_*, this function throws a ValueError. If share_options contains CURL_LOCK_DATA_COOKIE, this function throws a ValueError. If share_options contains a ...
 * @throws \TypeError If share_options is empty, this function throws a ValueError. If share_options contains a value not matching a CURL_LOCK_DATA_*, this function throws a ValueError. If share_options contains CURL_LOCK_DATA_COOKIE, this function throws a ValueError. If share_options contains a ...
 */
function curl_share_init_persistent(array $share_options): CurlSharePersistentHandle {}
