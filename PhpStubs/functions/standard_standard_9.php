<?php

/**
 * Merge two or more arrays recursively
 * @param array ...$arrays Variable list of arrays to recursively merge.
 * @return array An array of values resulted from merging the arguments together.
 */
function array_merge_recursive(
    array ...$arrays
): array {}

/**
 * array_replace() replaces the values of the first array with the same values from all the following arrays.
 * If a key from the first array exists in the second array, its value will be replaced by the value from the second array.
 * If the key exists in the second array, and not the first, it will be created in the first array.
 * If a key only exists in the first array, it will be left as is. If several arrays are passed for replacement,
 * they will be processed in order, the later arrays overwriting the previous values.
 * array_replace() is not recursive : it will replace values in the first array by whatever type is in the second array.
 * @param array $array The array in which elements are replaced.
 * @param array ...$replacements The array from which elements will be extracted.
 * @return array Prior to PHP 8.0, passing a value that was not an array raised a warning and returned null; since 8.0 a TypeError is thrown instead.
 */
function array_replace(
    array $array,
    array ...$replacements
): array {}

/**
 * Replaces elements from passed arrays into the first array recursively
 * @param array $array The array in which elements are replaced.
 * @param array ...$replacements The array from which elements will be extracted.
 * @return array an array. Prior to PHP 8.0, passing a value that was not an array raised a warning and returned null; since 8.0 a TypeError is thrown instead.
 */
function array_replace_recursive(
    array $array,
    array ...$replacements
): array {}

/**
 * Return all the keys or a subset of the keys of an array
 * @param array $array An array containing keys to return.
 * @param mixed $filter_value [optional] If specified, then only keys containing these values are returned.
 * @param bool $strict [optional] Determines if strict comparison (===) should be used during the search.
 * @return int[]|string[] an array of all the keys in input.
 */
function array_keys(array $array, mixed $filter_value, bool $strict = false): array {}

/**
 * Return all the values of an array
 * @param array $array The array.
 * @return array an indexed array of values.
 */
function array_values(array $array): array {}

/**
 * Counts all the values of an array
 * @param array $array The array of values to count
 * @return array an associative array of values from input as keys and their count as value.
 */
function array_count_values(array $array): array {}

/**
 * Return the values from a single column in the input array
 * @param array $array A multi-dimensional array (record set) from which to pull a column of values.
 * @param string|int|null $column_key The column of values to return. This value may be the integer key of the column you wish to retrieve, or it may be the string key name for an associative array. It may also be NULL to return complete arrays (useful together with index_key to reindex the array).
 * @param string|int|null $index_key [optional] The column to use as the index/keys for the returned array. This value may be the integer key of the column, or it may be the string key name.
 * @return array Returns an array of values representing a single column from the input array.
 * @since 5.5
 */
function array_column(array $array, string|int|null $column_key, string|int|null $index_key = null): array {}

/**
 * Return an array with elements in reverse order
 * @param array $array The input array.
 * @param bool $preserve_keys [optional] If set to true keys are preserved.
 * @return array the reversed array.
 */
function array_reverse(array $array, bool $preserve_keys = false): array {}

/**
 * Iteratively reduce the array to a single value using a callback function
 * @template TCarry
 * @template TValue
 * @param array<TValue> $array The input array.
 * @param callable(TCarry, TValue): TCarry $callback The callback function. Signature is callback ( mixed $carry , mixed $item ) : mixed mixed $carry The return value of the previous iteration; on the first iteration it holds the value of $initial. mixed $item Holds the current iteration value of the ...
 * @param TCarry $initial [optional] If the optional initial is available, it will be used at the beginning of the process, or as a final result in case the array is empty.
 * @return TCarry|null the resulting value. If the array is empty and initial is not passed, array_reduce returns null. Example use: array_reduce(['2', '3', '4'], function($ax, $dx) { return $ax . ", {$dx}"; }, '1')  // Returns '1, 2, 3, 4' array_reduce(['2', '3', '4'], function($ax, $dx) { return $ax ...
 */
function array_reduce(array $array, callable $callback, mixed $initial = null): mixed {}

/**
 * Pad array to the specified length with a value
 * @param array $array Initial array of values to pad.
 * @param int $length New size of the array.
 * @param mixed $value Value to pad if input is less than pad_size.
 * @return array a copy of the input padded to size specified by pad_size with value pad_value. If pad_size is positive then the array is padded on the right, if it's negative then on the left. If the absolute value of pad_size is less than or equal to the length of the input then no padding takes ...
 */
function array_pad(array $array, int $length, mixed $value): array {}

/**
 * Exchanges all keys with their associated values in an array
 * @template TKey of int|string
 * @template TValue of int|string
 * @param array<TKey, TValue> $array An array of key/value pairs to be flipped.
 * @return array<TValue, TKey> Returns the flipped array.
 */
function array_flip(array $array): array {}

/**
 * Changes the case of all keys in an array
 * @param array $array The array to work on
 * @param int $case Either CASE_UPPER or CASE_LOWER (default)
 * @return array an array with its keys lower or uppercased
 */
function array_change_key_case(array $array, int $case = CASE_LOWER): array {}

/**
 * Pick one or more random keys out of an array
 * @param array $array The input array.
 * @param int $num [optional] Specifies how many entries you want to pick.
 * @return int|string|array If you are picking only one entry, array_rand returns the key for a random entry. Otherwise, it returns an array of keys for the random entries. This is done so that you can pick random keys as well as values out of the array.
 * @throws \ValueError Throws a ValueError if array is empty, or if num is out of range.
 */
function array_rand(array $array, int $num = 1): array|string|int {}

/**
 * Removes duplicate values from an array
 * @param array $array The input array.
 * @param int $flags [optional] The optional second parameter sort_flags may be used to modify the sorting behavior using these values: Sorting type flags: SORT_REGULAR - compare items normally (don't change types) SORT_NUMERIC - compare items numerically SORT_STRING - compare items as strings ...
 * @return array the filtered array.
 */
function array_unique(array $array, int $flags = SORT_STRING): array {}

/**
 * Computes the intersection of arrays
 * @param array $array The array with main values to check.
 * @param array ...$arrays arrays to compare values against.
 * @return array an array containing all the values of array that are present in all the arguments. Note that keys are preserved.
 */
function array_intersect(array $array, array ...$arrays): array {}

/**
 * Computes the intersection of arrays using keys for comparison
 * @param array $array The array with main keys to check.
 * @param array ...$arrays Arrays to compare keys against.
 * @return array an array containing all the entries of array  which have keys that are present in all the arguments.
 */
function array_intersect_key(array $array, array ...$arrays): array {}

/**
 * Computes the intersection of arrays using a callback function on the keys for comparison
 * @param array $array Initial array for comparison of the arrays.
 * @param array $array2 First array to compare keys against.
 * @param callable $key_compare_func User supplied callback function to do the comparison.
 * @param ...$rest [optional]
 * @return array an array containing all the values of array which have matching keys that are present in all the arguments.
 */
function array_intersect_ukey(
    array $array,
    ...$rest
): array {}

/**
 * Computes the intersection of arrays, compares data by a callback function
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func The callback comparison function.
 * @param array ...$rest The user supplied callback function is used for comparison. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @return array an array containing all the values of array that are present in all the arguments.
 */
function array_uintersect(
    array $array,
    ...$rest
): array {}

/**
 * Computes the intersection of arrays with additional index check
 * @param array $array The array with main values to check.
 * @param array $arrays Arrays to compare values against.
 * @return array an associative array containing all the values in array that are present in all of the arguments.
 */
function array_intersect_assoc(array $array, array ...$arrays): array {}

/**
 * Computes the intersection of arrays with additional index check, compares data by a callback function
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func For comparison is used the user supplied callback function. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param array ...$rest
 * @return array an array containing all the values of array that are present in all the arguments.
 */
function array_uintersect_assoc(
    array $array,
    ...$rest
): array {}

/**
 * Computes the intersection of arrays with additional index check, compares indexes by a callback function
 * @param array $array Initial array for comparison of the arrays.
 * @param array $array2 First array to compare keys against.
 * @param callable $key_compare_func User supplied callback function to do the comparison.
 * @param array ...$rest
 * @return array the values of array whose values exist in all of the arguments.
 */
function array_intersect_uassoc(
    array $array,
    ...$rest
): array {}

/**
 * Computes the intersection of arrays with additional index check, compares data and indexes by separate callback functions
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func For comparison is used the user supplied callback function. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param callable $key_compare_func Key comparison callback function.
 * @param array ...$rest
 * @return array an array containing all the values and keys of array1 that are present in all the arguments.
 */
function array_uintersect_uassoc(
    array $array,
    ...$rest
): array {}

/**
 * Computes the difference of arrays
 * @param array $array The array to compare from
 * @param array ...$arrays Arrays to compare against
 * @return array an array containing all the entries from array that are not present in any of the other arrays. Keys in the array array are preserved.
 */
function array_diff(array $array, array ...$arrays): array {}

/**
 * Computes the difference of arrays using keys for comparison
 * @param array $array The array to compare from
 * @param array $arrays An array to compare against
 * @return array an array containing all the entries from array whose keys are absent from all of the other arrays.
 */
function array_diff_key(array $array, array ...$arrays): array {}

/**
 * Computes the difference of arrays using a callback function on the keys for comparison
 * @param array $array The array to compare from
 * @param array $array2 An array to compare against
 * @param callable $key_compare_func callback function to use. The callback function must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param array ...$rest [optional]
 * @return array an array containing all the entries from array that are not present in any of the other arrays.
 */
function array_diff_ukey(
    array $array,
    ...$rest,
): array {}

/**
 * Computes the difference of arrays by using a callback function for data comparison
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func The callback comparison function. The user supplied callback function is used for comparison. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param array ...$rest [optional]
 * @return array an array containing all the values of array that are not present in any of the other arguments.
 */
function array_udiff(
    array $array,
    ...$rest,
): array {}

/**
 * Computes the difference of arrays with additional index check
 * @param array $array The array to compare from
 * @param array $arrays An array to compare against
 * @return array an array containing all the values from array that are not present in any of the other arrays.
 */
function array_diff_assoc(
    array $array,
    array ...$arrays
): array {}

/**
 * Computes the difference of arrays with additional index check, compares data by a callback function
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func The callback comparison function. The user supplied callback function is used for comparison. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param array ...$rest [optional]
 * @return array returns an array containing all the values from array that are not present in any of the other arguments. Note that the keys are used in the comparison unlike array_diff and array_udiff. The comparison of arrays' data is performed by using an user-supplied callback. In this aspect the ...
 */
function array_udiff_assoc(
    array $array,
    ...$rest,
): array {}

/**
 * Computes the difference of arrays with additional index check which is performed by a user supplied callback function
 * @param array $array The array to compare from
 * @param array $array2 An array to compare against
 * @param callable $key_compare_func callback function to use. The callback function must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the second.
 * @param array ...$rest [optional]
 * @return array an array containing all the values and keys from array that are not present in any of the other arrays.
 */
function array_diff_uassoc(
    array $array,
    ...$rest,
): array {}

/**
 * Computes the difference of arrays with additional index check, compares data and indexes by a callback function
 * @param array $array The first array.
 * @param array $array2 The second array.
 * @param callable $data_compare_func The callback comparison function. The user supplied callback function is used for comparison. It must return an integer less than, equal to, or greater than zero if the first argument is considered to be respectively less than, equal to, or greater than the ...
 * @param callable $key_compare_func The comparison of keys (indices) is done also by the callback function key_compare_func. This behaviour is unlike what array_udiff_assoc does, since the latter compares the indices by using an internal function.
 * @param array ...$rest [optional]
 * @return array an array containing all the values and keys from array that are not present in any of the other arguments.
 */
function array_udiff_uassoc(
    array $array,
    ...$rest
): array {}

/**
 * Calculate the sum of values in an array
 * @param array $array The input array.
 * @return int|float the sum of values as an integer or float.
 */
function array_sum(array $array): int|float {}

/**
 * Calculate the product of values in an array
 * @param array $array The array.
 * @return int|float the product as an integer or float.
 */
function array_product(array $array): int|float {}

/**
 * Iterates over each value in the array
 * passing them to the callback function.
 * If the callback function returns true, the
 * current value from array is returned into
 * the result array. Array keys are preserved.
 * @param array $array The array to iterate over
 * @param callable|null $callback [optional] The callback function to use If no callback is supplied, all entries of input equal to false (see converting to boolean) will be removed.
 * @param int $mode [optional] Flag determining what arguments are sent to callback: ARRAY_FILTER_USE_KEY - pass key as the only argument to callback instead of the value ARRAY_FILTER_USE_BOTH - pass both value and key as arguments to callback instead of the value
 * @return array the filtered array.
 */
function array_filter(array $array, ?callable $callback = null, int $mode = 0): array {}

/**
 * Applies the callback to the elements of the given arrays
 * @param callable|null $callback Callback function to run for each element in each array.
 * @param array $array An array to run through the callback function.
 * @param array ...$arrays Supplementary variable list of array arguments to run through the callback function.
 * @return array an array containing all the elements of arr1 after applying the callback function to each one.
 */
function array_map(
    ?callable $callback,
    array $array,
    array ...$arrays
): array {}

/**
 * Split an array into chunks
 * @param array $array The array to work on
 * @param int $length The size of each chunk
 * @param bool $preserve_keys [optional] When set to true keys will be preserved. Default is false which will reindex the chunk numerically
 * @return array a multidimensional numerically indexed array, starting with zero, with each dimension containing size elements.
 * @throws \ValueError If length is less than 1, a ValueError will be thrown.
 */
function array_chunk(array $array, int $length, bool $preserve_keys = false): array {}

/**
 * Creates an array by using one array for keys and another for its values
 * @param array $keys Array of keys to be used. Illegal values for key will be converted to string.
 * @param array $values Array of values to be used
 * @return array the combined array
 * @throws \ValueError if the number of elements in keys and values does not match.
 */
function array_combine(array $keys, array $values): array {}

/**
 * Checks if the given key or index exists in the array
 * @param int|string $key Value to check.
 * @param array|ArrayObject $array An array with keys to check.
 * @return bool true on success or false on failure.
 */
function array_key_exists($key, array $array): bool {}

/**
 * Gets the first key of an array
 *
 * Get the first key of the given array without affecting the internal array pointer.
 * @param array $array An array
 * @return string|int|null Returns the first key of array if the array is not empty; NULL otherwise.
 * @since 7.3
 */
function array_key_first(array $array): string|int|null {}

/**
 * Gets the last key of an array
 *
 * Get the last key of the given array without affecting the internal array pointer.
 * @param array $array An array
 * @return string|int|null Returns the last key of array if the array is not empty; NULL otherwise.
 * @since 7.3
 */
function array_key_last(array $array): string|int|null {}

/**
 * Checks whether a given array is a list
 *
 * Determines if the given array is a list. An array is considered a list if its keys consist of
 * consecutive numbers from 0 to count($array)-1.
 * @param array $array An array
 * @return bool return true if the array keys are 0 .. count($array)-1 in that order. For other arrays, it returns false. For non-arrays, it throws a TypeError.
 * @since 8.1
 */
function array_is_list(array $array): bool {}

/**
 * Alias:
 * current
 * @param array|ArrayAccess $array
 * @return mixed
 */
function pos(object|array $array): mixed {}

/**
 * Alias:
 * \count
 * @param array|Countable $value
 * @param int $mode [optional]
 * @return int<0, max>
 */
function sizeof(Countable|array $value, int $mode = COUNT_NORMAL): int {}

/**
 * Checks if the given key or index exists in the array. The name of this function is array_key_exists() in PHP > 4.0.6.
 * @param int|string $key Value to check.
 * @param array $array An array with keys to check.
 * @return bool true on success or false on failure.
 */
function key_exists($key, array $array): bool {}

/**
 * Checks if assertion is FALSE
 * @param mixed $assertion The assertion. In PHP 5, this must be either a string to be evaluated or a boolean to be tested. In PHP 7, this may also be any expression that returns a value, which will be executed and the result used to indicate whether the assertion succeeded or failed. Since 7.2.0 ...
 * @param string $description [optional] An optional description that will be included in the failure message if the assertion fails.
 * @return bool false if the assertion is false, true otherwise.
 */
function assert(
    mixed $assertion,
    Throwable|string|null $description = null
): bool {}

/**
 * Set/get the various assert flags
 * @param int $option Assert Options Option INI Setting Default value Description ASSERT_ACTIVE assert.active 1 enable assert evaluation ASSERT_WARNING assert.warning 1 issue a PHP warning for each failed assertion ASSERT_BAIL assert.bail 0 terminate execution on failed assertions ASSERT_QUIET_EVAL ...
 * @param mixed $value [optional] An optional new value for the option.
 * @return mixed The original setting of any option.
 * @throws \ValueError If option is not a valid option a ValueError is thrown.
 * @deprecated
 */
function assert_options(int $option, mixed $value): mixed {}

/**
 * Compares two "PHP-standardized" version number strings
 * @param string $version1 First version number.
 * @param string $version2 Second version number.
 * @param string|null $operator [optional] If you specify the third optional operator argument, you can test for a particular relationship. The possible operators are: <, lt, <=, le, >, gt, >=, ge, ==, =, eq, !=, <>, ne respectively. This parameter is case-sensitive, so values should be lowercase.
 * @return int|bool By default, version_compare returns -1 if the first version is lower than the second, 0 if they are equal, and 1 if the second is lower. When using the optional operator argument, the function will return true if the relationship is the one specified by the operator, false ...
 * @throws ValueError when a non-supported operator is provided.
 */
function version_compare(
    string $version1,
    string $version2,
    ?string $operator = null
): int|bool {}

/**
 * Convert a pathname and a project identifier to a System V IPC key
 * @param string $filename Path to an accessible file.
 * @param string $project_id Project identifier. This must be a one character string.
 * @return int On success the return value will be the created key value, otherwise -1 is returned.
 */
function ftok(string $filename, string $project_id): int {}

/**
 * Perform the rot13 transform on a string
 * @param string $string The input string.
 * @return string the ROT13 version of the given string.
 */
function str_rot13(string $string): string {}

/**
 * Retrieve list of registered filters
 * @return list<string> an indexed array containing the name of all stream filters available.
 */
function stream_get_filters(): array {}

/**
 * Check if a stream is a TTY
 * @param resource $stream
 * @return bool Returns true on success or false on failure.
 * @since 7.2
 */
function stream_isatty($stream): bool {}

/**
 * Register a user defined stream filter
 * @param string $filter_name The filter name to be registered.
 * @param string $class To implement a filter, you need to define a class as an extension of php_user_filter with a number of member functions as defined below. When performing read/write operations on the stream to which your filter is attached, PHP will pass the data through your filter (and any ...
 * @return bool true on success or false on failure. stream_filter_register will return false if the filtername is already defined.
 */
function stream_filter_register(string $filter_name, string $class): bool {}

/**
 * Return a bucket object from the brigade for operating on
 * @param resource $brigade The brigade to return a bucket object from.
 * @return object|null Returns a bucket object or null.
 */
function stream_bucket_make_writeable($brigade): object|null {}

/**
 * Prepend bucket to brigade
 * @param resource $brigade brigade is a resource pointing to a bucket brigade which contains one or more bucket objects.
 * @param object $bucket A bucket object.
 * @return void No value is returned.
 */
function stream_bucket_prepend($brigade, object $bucket): void {}

/**
 * Append bucket to brigade
 * @param resource $brigade
 * @param object $bucket
 * @return void
 */
function stream_bucket_append($brigade, object $bucket): void {}

/**
 * Create a new bucket for use on the current stream
 * @param resource $stream
 * @param string $buffer
 * @return object
 */
function stream_bucket_new($stream, string $buffer): object {}

/**
 * Add URL rewriter values
 * @param string $name The variable name.
 * @param string $value The variable value.
 * @return bool true on success or false on failure.
 */
function output_add_rewrite_var(string $name, string $value): bool {}

/**
 * Reset URL rewriter values
 *
 * Version
 * Description
 *
 * 7.1.0
 *
 * Before PHP 7.1.0, rewrite vars set by output_add_rewrite_var()
 * use the same Session module trans sid output buffer. Since PHP 7.1.0,
 * dedicated output buffer is used and output_reset_rewrite_vars()
 * only removes rewrite vars defined by output_add_rewrite_var().
 * @return bool true on success or false on failure.
 */
function output_reset_rewrite_vars(): bool {}

/**
 * Returns directory path used for temporary files
 * @return string the path of the temporary directory.
 * @since 5.2
 */
function sys_get_temp_dir(): string {}

/**
 * Get the contents of the realpath cache.
 * @return array Returns an array of realpath cache entries. The keys are original path entries, and the values are arrays of data items, containing the resolved path, expiration date, and other options kept in the cache.
 * @since 5.3
 */
function realpath_cache_get(): array {}

/**
 * Get the amount of memory used by the realpath cache.
 * @return int Returns how much memory realpath cache is using.
 * @since 5.3
 */
function realpath_cache_size(): int {}

/**
 * It returns the same result as (array) $object, with the
 * exception that it ignores overloaded array casts, such as used by
 * ArrayObject.
 * @param object $object An object instance.
 * @return array returns the mangled object properties
 * @since 7.4
 */
function get_mangled_object_vars(object $object): array {}

/**
 * Get the type or object name of a variable
 * @param mixed $value The variable being type checked.
 * @return string Possibles values for the returned string are: - "int" - "float" - "bool" - "string" - "array" - "null" - A class name for named classes - "class@anonymous" for an anonymous classes - "resource (xxx)" for any resources where "xxx" is a name of resource - "resource (closed)" for closed ...
 * @since 8.0
 */
function get_debug_type(mixed $value): string {}

/**
 * A more obvious and type-safe form of "(int) $resource"
 * @param resource $resource The evaluated resource handle.
 * @return int The int identifier for the given resource. This function is essentially an int cast of resource to make it easier to retrieve the resource ID.
 * @since 8.0
 */
function get_resource_id($resource): int {}
