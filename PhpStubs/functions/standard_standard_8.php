<?php

/**
 * Generate a system log message
 * @param int $priority priority is a combination of the facility and the level. Possible values are: syslog Priorities (in descending order) Constant Description LOG_EMERG system is unusable LOG_ALERT action must be taken immediately LOG_CRIT critical conditions LOG_ERR error conditions LOG_WARNING ...
 * @param string $message The message to send, except that the two characters %m will be replaced by the error message string (strerror) corresponding to the present value of errno.
 */
function syslog(int $priority, string $message): true {}

/**
 * Close connection to system logger
 */
function closelog(): true {}

/**
 * Registers a function that will be called when PHP starts sending output.
 * The callback is executed just after PHP prepares all headers to be sent,
 *
 * and before any other output is sent, creating a window to manipulate the outgoing headers before being sent.
 * @param callable $callback Function called just before the headers are sent.
 * @return bool true on success or false on failure.
 */
function header_register_callback(callable $callback): bool {}

/**
 * Get the size of an image from a string.
 * @param string $string The image data, as a string.
 * @param array &$image_info [optional] This optional parameter allows you to extract some extended information from the image file. Currently, this will return the different JPG APP markers as an associative array. Some programs use these APP markers to embed text information in images. A very common ...
 * @return array|false Returns an array with 7 elements. Index 0 and 1 contains respectively the width and the height of the image. Index 2 is one of the IMAGETYPE_XXX constants indicating the type of the image. Index 3 is a text string with the correct height="yyy" width="xxx" string that can be used ...
 * @since 5.4
 * @since 5.4
 */
function getimagesizefromstring(string $string, &$image_info = null): array|false {}

/**
 * Set the stream chunk size.
 * @param resource $stream The target stream.
 * @param int $size The desired new chunk size.
 * @return int|false Returns the previous chunk size on success. Will return FALSE if chunk_size is less than 1 or greater than PHP_INT_MAX.
 * @since 5.4
 * @throws \ValueError A ValueError is thrown if size is less than 1 or greater than PHP_INT_MAX.
 */
function stream_set_chunk_size($stream, int $size): int {}

/**
 * Initializes all syslog related variables
 * @return void No value is returned. This function has been DEPRECATED as of PHP 5.3.0 and REMOVED as of PHP 5.4.0.
 * @removed 5.4
 * @deprecated
 */
function define_syslog_variables() {}

/**
 * Calculate the metaphone key of a string
 * @param string $string The input string.
 * @param int $max_phonemes [optional] This parameter restricts the returned metaphone key to phonemes characters in length. The default value of 0 means no restriction.
 * @return string|false the metaphone key as a string, or FALSE on failure
 */
function metaphone(string $string, int $max_phonemes = 0): string {}

/**
 * Turn on output buffering
 * @param callable|null $callback An optional output_callback function may be specified. This function takes a string as a parameter and should return a string. The function will be called when the output buffer is flushed (sent) or cleaned (with ob_flush, ob_clean or similar function) or when the ...
 * @param int $chunk_size If the optional parameter chunk_size is passed, the buffer will be flushed after any output call which causes the buffer's length to equal or exceed chunk_size. Default value 0 means that the function is called only in the end, other special value 1 sets chunk_size to 4096.
 * @param int $flags [optional] The flags parameter is a bitmask that controls the operations that can be performed on the output buffer. The default is to allow output buffers to be cleaned, flushed and removed, which can be set explicitly via PHP_OUTPUT_HANDLER_CLEANABLE | ...
 * @return bool true on success or false on failure.
 */
function ob_start($callback = null, int $chunk_size = 0, int $flags = PHP_OUTPUT_HANDLER_STDFLAGS): bool {}

/**
 * Flush (send) the output buffer
 * @return bool Returns true on success or false on failure.
 */
function ob_flush(): bool {}

/**
 * Clean (erase) the output buffer
 * @return bool Returns true on success or false on failure.
 */
function ob_clean(): bool {}

/**
 * Flush (send) the output buffer and turn off output buffering
 * @return bool true on success or false on failure. Reasons for failure are first that you called the function without an active buffer or that for some reason a buffer could not be deleted (possible for special buffer).
 */
function ob_end_flush(): bool {}

/**
 * Clean (erase) the output buffer and turn off output buffering
 * @return bool true on success or false on failure. Reasons for failure are first that you called the function without an active buffer or that for some reason a buffer could not be deleted (possible for special buffer).
 */
function ob_end_clean(): bool {}

/**
 * Flush the output buffer, return it as a string and turn off output buffering
 * @return string|false the output buffer or false if no buffering is active.
 */
function ob_get_flush(): string|false {}

/**
 * Get current buffer contents and delete current output buffer
 * @return string|false the contents of the output buffer and end output buffering. If output buffering isn't active then false is returned.
 */
function ob_get_clean(): string|false {}

/**
 * Return the length of the output buffer
 * @return int|false the length of the output buffer contents or false if no buffering is active.
 */
function ob_get_length(): int|false {}

/**
 * Return the nesting level of the output buffering mechanism
 * @return int the level of nested output buffering handlers or zero if output buffering is not active.
 */
function ob_get_level(): int {}

/**
 * Get status of output buffers
 * @param bool $full_status [optional] true to return all active output buffer levels. If false or not set, only the top level output buffer is returned.
 * @return array If called without the full_status parameter or with full_status = false a simple array with the following elements is returned: Array ( [level] => 2 [type] => 0 [status] => 0 [name] => URL-Rewriter [del] => 1 ) KeyValue levelOutput nesting level typePHP_OUTPUT_HANDLER_INTERNAL (0) or ...
 */
function ob_get_status(bool $full_status = false): array {}

/**
 * Return the contents of the output buffer
 * @return string|false This will return the contents of the output buffer or false, if output buffering isn't active.
 */
function ob_get_contents(): string|false {}

/**
 * Turn implicit flush on/off
 * @param int|bool $enable [optional] 1|TRUE to turn implicit flushing on, 0|FALSE turns it off. default: 1|TRUE
 * @return void No value is returned.
 */
function ob_implicit_flush(bool $enable = true): void {}

/**
 * List all output handlers in use
 * @return array This will return an array with the output handlers in use (if any). If output_buffering is enabled or an anonymous function was used with ob_start, ob_list_handlers will return "default output handler".
 */
function ob_list_handlers(): array {}

/**
 * Sort an array by key in ascending order
 * @param array &$array The input array.
 * @param int $flags You may modify the behavior of the sort using the optional parameter sort_flags, for details see sort.
 */
function ksort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array by key in reverse order
 * @param array &$array The input array.
 * @param int $flags You may modify the behavior of the sort using the optional parameter sort_flags, for details see sort.
 */
function krsort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array using a "natural order" algorithm
 * @param array &$array The input array.
 */
function natsort(array &$array): true {}

/**
 * Sort an array using a case insensitive "natural order" algorithm
 * @param array &$array The input array.
 */
function natcasesort(array &$array): true {}

/**
 * Sort an array and maintain index association
 * @param array &$array The input array.
 * @param int $flags You may modify the behavior of the sort using the optional parameter sort_flags, for details see sort.
 */
function asort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array in reverse order and maintain index association
 * @param array &$array The input array.
 * @param int $flags You may modify the behavior of the sort using the optional parameter sort_flags, for details see sort.
 */
function arsort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array
 * @param array &$array The input array.
 * @param int $flags The optional second parameter sort_flags may be used to modify the sorting behavior using these values. Sorting type flags: SORT_REGULAR - compare items normally (don't change types)
 */
function sort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array in reverse order
 * @param array &$array The input array.
 * @param int $flags You may modify the behavior of the sort using the optional parameter sort_flags, for details see sort.
 */
function rsort(array &$array, int $flags = SORT_REGULAR): true {}

/**
 * Sort an array by values using a user-defined comparison function
 * @param array &$array The input array.
 * @param callable $callback The comparison function must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @return true Always returns true.
 */
function usort(array &$array, callable $callback): true {}

/**
 * Sort an array with a user-defined comparison function and maintain index association
 * @param array &$array The input array.
 * @param callable $callback See usort and uksort for examples of user-defined comparison functions.
 */
function uasort(array &$array, callable $callback): true {}

/**
 * Sort an array by keys using a user-defined comparison function
 * @param array &$array The input array.
 * @param callable $callback The callback comparison function. Function cmp_function should accept two parameters which will be filled by pairs of array keys. The comparison function must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively ...
 */
function uksort(array &$array, callable $callback): true {}

/**
 * Shuffle an array
 * @param array &$array The array.
 */
function shuffle(array &$array): true {}

/**
 * Apply a user function to every member of an array
 * @param array|object &$array The input array.
 * @param callable $callback Typically, funcname takes on two parameters. The array parameter's value being the first, and the key/index second. If funcname needs to be working with the actual values of the array, specify the first parameter of funcname as a reference. Then, any changes made to those ...
 * @param mixed $arg [optional] If the optional userdata parameter is supplied, it will be passed as the third parameter to the callback funcname.
 * @throws \ArgumentCountError As of PHP 7.1.0, an ArgumentCountError will be thrown if the callback function requires more than 2 parameters (the value and key of the array member), or more than 3 parameters if the arg is also passed. Previously, in this case an error of level E_WARNING would be ...
 */
function array_walk(object|array &$array, callable $callback, mixed $arg): true {}

/**
 * Apply a user function recursively to every member of an array
 * @param array|object &$array The input array.
 * @param callable $callback Typically, funcname takes on two parameters. The input parameter's value being the first, and the key/index second. If funcname needs to be working with the actual values of the array, specify the first parameter of funcname as a reference. Then, any changes made to those ...
 * @param mixed $arg [optional] If the optional userdata parameter is supplied, it will be passed as the third parameter to the callback funcname.
 */
function array_walk_recursive(object|array &$array, callable $callback, mixed $arg): true {}

/**
 * Counts all elements in an array, or something in an object.
 * For objects, if you have SPL installed, you can hook into count() by implementing interface Countable.
 * The interface has exactly one method, Countable::count(), which returns the return value for the count() function.
 * Please see the Array section of the manual for a detailed explanation of how arrays are implemented and used in PHP.
 * @param array|Countable $value The array or the object.
 * @param int $mode [optional] If the optional mode parameter is set to COUNT_RECURSIVE (or 1), count will recursively count the array. This is particularly useful for counting all the elements of a multidimensional array. count does not detect infinite recursion.
 * @return int<0,max> the number of elements in var, which is typically an array, since anything else will have one element. If var is not an array or an object with implemented Countable interface, 1 will be returned. There is one exception, if var is null, 0 will be returned. Caution: count may ...
 */
function count(Countable|array $value, int $mode = COUNT_NORMAL): int {}

/**
 * Set the internal pointer of an array to its last element
 * @param array|object &$array The array. This array is passed by reference because it is modified by the function. This means you must pass it a real variable and not a function returning an array because only actual variables may be passed by reference.
 * @return mixed|false the value of the last element or false for empty array.
 */
function end(object|array &$array): mixed {}

/**
 * Rewind the internal array pointer
 * @param array|object &$array The input array.
 * @return mixed|false the array value in the previous place that's pointed to by the internal array pointer, or false if there are no more elements.
 */
function prev(object|array &$array): mixed {}

/**
 * Advance the internal array pointer of an array
 * @param array|object &$array The array being affected.
 * @return mixed|false the array value in the next place that's pointed to by the internal array pointer, or false if there are no more elements.
 */
function next(object|array &$array): mixed {}

/**
 * Set the internal pointer of an array to its first element
 * @param array|object &$array The input array.
 * @return mixed|false the value of the first array element, or false if the array is empty.
 */
function reset(object|array &$array): mixed {}

/**
 * Return the current element in an array
 * @param array|object $array The array.
 * @return mixed|false The current function simply returns the value of the array element that's currently being pointed to by the internal pointer. It does not move the pointer in any way. If the internal pointer points beyond the end of the elements list or the array is empty, current returns false.
 */
function current(object|array $array): mixed {}

/**
 * Fetch a key from an array
 * @param array|object $array The array.
 * @return int|string|null The key function simply returns the key of the array element that's currently being pointed to by the internal pointer. It does not move the pointer in any way. If the internal pointer points beyond the end of the elements list or the array is empty, key returns null.
 */
function key(object|array $array): string|int|null {}

/**
 * Find lowest value
 * @param array|mixed $value Array to look through or first value to compare
 * @param mixed ...$values any comparable value
 * @return mixed min returns the numerically lowest of the parameter values.
 * @throws \ValueError If an empty array is passed, min throws a ValueError.
 */
function min(
    mixed $value,
    mixed ...$values
): mixed {}

/**
 * Find highest value
 * @param array|mixed $value Array to look through or first value to compare
 * @param mixed ...$values any comparable value
 * @return mixed max returns the numerically highest of the parameter values, either within a arg array or two arguments.
 * @throws \ValueError If an empty array is passed, max throws a ValueError.
 */
function max(
    mixed $value,
    mixed ...$values
): mixed {}

/**
 * Checks if a value exists in an array
 * @param mixed $needle The searched value. If needle is a string, the comparison is done in a case-sensitive manner.
 * @param array $haystack The array.
 * @param bool $strict [optional] If the third parameter strict is set to true then the in_array function will also check the types of the needle in the haystack.
 * @return bool true if needle is found in the array, false otherwise.
 */
function in_array(mixed $needle, array $haystack, bool $strict = false): bool {}

/**
 * Searches the array for a given value and returns the first corresponding key if successful
 * @param mixed $needle The searched value. If needle is a string, the comparison is done in a case-sensitive manner.
 * @param array $haystack The array.
 * @param bool $strict [optional] If the third parameter strict is set to true then the array_search function will also check the types of the needle in the haystack.
 * @return int|string|false the key for needle if it is found in the array, false otherwise. If needle is found in haystack more than once, the first matching key is returned. To return the keys for all matching values, use array_keys with the optional search_value parameter instead.
 */
function array_search(mixed $needle, array $haystack, bool $strict = false): string|int|false {}

/**
 * Import variables into the current symbol table from an array
 * @param array &$array Note that prefix is only required if extract_type is EXTR_PREFIX_SAME, EXTR_PREFIX_ALL, EXTR_PREFIX_INVALID or EXTR_PREFIX_IF_EXISTS. If the prefixed result is not a valid variable name, it is not imported into the symbol table. Prefixes are automatically separated from the ...
 * @param int $flags The way invalid/numeric keys and collisions are treated is determined by the extract_type. It can be one of the following values: EXTR_OVERWRITE If there is a collision, overwrite the existing variable.
 * @param string $prefix Only overwrite the variable if it already exists in the current symbol table, otherwise do nothing. This is useful for defining a list of valid variables and then extracting only those variables you have defined out of $_REQUEST, for example.
 * @return int the number of variables successfully imported into the symbol table.
 */
function extract(
    array &$array,
    int $flags = EXTR_OVERWRITE,
    string $prefix = ""
): int {}

/**
 * Create array containing variables and their values
 * @param mixed $var_name compact takes a variable number of parameters. Each parameter can be either a string containing the name of the variable, or an array of variable names. The array can contain other arrays of variable names inside it; compact handles it recursively.
 * @param mixed ...$var_names
 * @return array the output array with all the variables added to it.
 */
function compact($var_name, ...$var_names): array {}

/**
 * Fill an array with values
 * @param int $start_index The first index of the returned array. Supports non-negative indexes only.
 * @param int $count Number of elements to insert
 * @param mixed $value Value to use for filling
 * @return array the filled array
 * @throws \ValueError Throws a ValueError if count is out of range.
 */
function array_fill(int $start_index, int $count, mixed $value): array {}

/**
 * Fill an array with values, specifying keys
 * @param array $keys Array of values that will be used as keys. Illegal values for key will be converted to string.
 * @param mixed $value Value to use for filling
 * @return array the filled array
 */
function array_fill_keys(array $keys, mixed $value): array {}

/**
 * Create an array containing a range of elements
 * @param mixed $start First value of the sequence.
 * @param mixed $end The sequence is ended upon reaching the end value.
 * @param positive-int|float $step [optional] If a step value is given, it will be used as the increment between elements in the sequence. step should be given as a positive number. If not specified, step will default to 1.
 * @return array an array of elements from start to end, inclusive.
 * @throws \ValueError If step is 0, a ValueError is thrown. If start, end, or step is not is_finite, a ValueError is thrown. If step is negative, but the produced range is increasing (i.e. $start <= $end), a ValueError is thrown. If start or end is the empty string '', an E_WARNING is emitted and the ...
 */
function range(
    string|int|float $start,
    string|int|float $end,
    int|float $step = 1
): array {}

/**
 * Sort multiple or multi-dimensional arrays
 * @param array &$array An array being sorted.
 * @param mixed &...$rest [optional] More arrays, optionally followed by sort order and flags. Only elements corresponding to equivalent elements in previous arrays are compared. In other words, the sort is lexicographical.
 * @return bool true on success or false on failure.
 */
function array_multisort(
    &$array,
    &...$rest
): bool {}

/**
 * Push elements onto the end of array
 * Since 7.3.0 this function can be called with only one parameter.
 * For earlier versions at least two parameters are required.
 * @param array &$array The input array.
 * @param mixed ...$values The pushed variables.
 * @return int the number of elements in the array.
 */
function array_push(
    array &$array,
    mixed ...$values
): int {}

/**
 * Pop the element off the end of array
 * @param array &$array The array to get the value from.
 * @return mixed|null the last value of array. If array is empty (or is not an array), null will be returned.
 */
function array_pop(array &$array): mixed {}

/**
 * Shift an element off the beginning of array
 * @param array &$array The input array.
 * @return mixed|null the shifted value, or null if array is empty or is not an array.
 */
function array_shift(array &$array): mixed {}

/**
 * Prepend elements to the beginning of an array
 * Since 7.3.0 this function can be called with only one parameter.
 * For earlier versions at least two parameters are required.
 * @param array &$array The input array.
 * @param mixed ...$values The prepended variables.
 * @return int the number of elements in the array.
 */
function array_unshift(array &$array, mixed ...$values): int {}

/**
 * Remove a portion of the array and replace it with something else
 * @param array &$array The input array.
 * @param int $offset If offset is positive then the start of removed portion is at that offset from the beginning of the input array. If offset is negative then it starts that far from the end of the input array.
 * @param int|null $length [optional] If length is omitted, removes everything from offset to the end of the array. If length is specified and is positive, then that many elements will be removed. If length is specified and is negative then the end of the removed portion will be that many elements ...
 * @param mixed $replacement If replacement array is specified, then the removed elements are replaced with elements from this array. If offset and length are such that nothing is removed, then the elements from the replacement array are inserted in the place specified by the offset. Note that keys in ...
 * @return array the array consisting of the extracted elements.
 */
function array_splice(array &$array, int $offset, ?int $length = null, mixed $replacement = []): array {}

/**
 * Extract a slice of the array
 * @param array $array The input array.
 * @param int $offset If offset is non-negative, the sequence will start at that offset in the array. If offset is negative, the sequence will start that far from the end of the array.
 * @param int|null $length [optional] If length is given and is positive, then the sequence will have that many elements in it. If length is given and is negative then the sequence will stop that many elements from the end of the array. If it is omitted, then the sequence will have everything from ...
 * @param bool $preserve_keys [optional] Note that array_slice will reorder and reset the array indices by default. You can change this behaviour by setting preserve_keys to true.
 * @return array the slice.
 */
function array_slice(array $array, int $offset, ?int $length = null, bool $preserve_keys = false): array {}

/**
 * Merges the elements of one or more arrays together (if the input arrays have the same string keys, then the later value for that key will overwrite the previous one; if the arrays contain numeric keys, the later value will be appended)
 * Since 7.4.0 this function can be called without any parameter, and it will return empty array.
 * @param array ...$arrays Variable list of arrays to merge.
 * @return array the resulting array.
 */
function array_merge(
    array ...$arrays
): array {}

/**
 * Gets the first value of an array
 *
 * Get the first value of the given array.
 * @template TKey
 * @template TValue
 * @param array<TKey, TValue> $array An array.
 * @return TValue|null Returns the first value of array if the array is not empty; null otherwise.
 * @since 8.5
 */
function array_first(array $array): mixed {}

/**
 * Gets the last value of an array
 *
 * Get the last value of the given array.
 * @template TKey
 * @template TValue
 * @param array<TKey, TValue> $array An array.
 * @return TValue|null Returns the last value of array if the array is not empty; null otherwise.
 * @since 8.5
 */
function array_last(array $array): mixed {}
