<?php

/**
 * Gets a specific external variable by name and optionally filters it
 * @param int $type One of INPUT_GET, INPUT_POST, INPUT_COOKIE, INPUT_SERVER, or INPUT_ENV.
 * @param string $var_name Name of a variable to get.
 * @param int $filter [optional] The ID of the filter to apply. The manual page lists the available filters.
 * @param array|int $options Associative array of options or bitwise disjunction of flags. If filter accepts options, flags can be provided in "flags" field of array.
 * @return mixed Value of the requested variable on success, FALSE if the filter fails, or NULL if the variable_name variable is not set. If the flag FILTER_NULL_ON_FAILURE is used, it returns FALSE if the variable is not set and NULL if the filter fails.
 */
function filter_input(int $type, string $var_name, int $filter = FILTER_DEFAULT, array|int $options = 0): mixed {}

/**
 * Filters a variable with a specified filter
 * @param mixed $value Value to filter.
 * @param int $filter [optional] The ID of the filter to apply. The manual page lists the available filters.
 * @param array|int $options Associative array of options or bitwise disjunction of flags. If filter accepts options, flags can be provided in "flags" field of array. For the "callback" filter, callable type should be passed. The callback must accept one argument, the value to be filtered, and return ...
 * @return mixed the filtered data, or FALSE if the filter fails.
 */
function filter_var(mixed $value, int $filter = FILTER_DEFAULT, array|int $options = 0): mixed {}

/**
 * Gets external variables and optionally filters them
 * @param int $type One of INPUT_GET, INPUT_POST, INPUT_COOKIE, INPUT_SERVER, or INPUT_ENV.
 * @param array|int $options [optional] An array defining the arguments. A valid key is a string containing a variable name and a valid value is either a filter type, or an array optionally specifying the filter, flags and options. If the value is an array, valid keys are filter which specifies the ...
 * @param bool $add_empty [optional] Add missing keys as NULL to the return value.
 * @return array|false|null An array containing the values of the requested variables on success, or FALSE on failure. An array value will be FALSE if the filter fails, or NULL if the variable is not set. Or if the flag FILTER_NULL_ON_FAILURE is used, it returns FALSE if the variable is not set and ...
 */
function filter_input_array(int $type, array|int $options = FILTER_DEFAULT, bool $add_empty = true): array|false|null {}

/**
 * Gets multiple variables and optionally filters them
 * @param array $array An array with string keys containing the data to filter.
 * @param array|int $options [optional] An array defining the arguments. A valid key is a string containing a variable name and a valid value is either a filter type, or an array optionally specifying the filter, flags and options. If the value is an array, valid keys are filter which specifies the ...
 * @param bool $add_empty [optional] Add missing keys as NULL to the return value.
 * @return array|false|null An array containing the values of the requested variables on success, or FALSE on failure. An array value will be FALSE if the filter fails, or NULL if the variable is not set.
 */
function filter_var_array(array $array, array|int $options = FILTER_DEFAULT, bool $add_empty = true): array|false|null {}

/**
 * Returns a list of all supported filters
 * @return array an array of names of all supported filters, empty array if there are no such filters. Indexes of this array are not filter IDs, they can be obtained with filter_id from a name instead.
 */
function filter_list(): array {}

/**
 * Checks if variable of specified type exists
 * @param int $input_type One of INPUT_GET, INPUT_POST, INPUT_COOKIE, INPUT_SERVER, or INPUT_ENV.
 * @param string $var_name Name of a variable to check.
 * @return bool TRUE on success or FALSE on failure.
 */
function filter_has_var(int $input_type, string $var_name): bool {}

/**
 * Returns the filter ID belonging to a named filter
 * @param string $name Name of a filter to get.
 * @return int|false ID of a filter on success or FALSE if filter doesn't exist.
 */
function filter_id(string $name): int|false {}
