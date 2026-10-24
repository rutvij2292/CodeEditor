<?php

/**
 * Gets the version of the current Zend engine
 * @return string the Zend Engine version number, as a string.
 */
function zend_version(): string {}

/**
 * Returns the number of arguments passed to the function
 * @return int the number of arguments passed into the current user-defined function.
 */
function func_num_args(): int {}

/**
 * Return an item from the argument list
 * @param int $position The argument offset. Function arguments are counted starting from zero.
 * @return mixed|false the specified argument, or false on error.
 */
function func_get_arg(int $position): mixed {}

/**
 * Returns an array comprising a function's argument list
 * @return array an array in which each element is a copy of the corresponding member of the current user-defined function's argument list.
 */
function func_get_args(): array {}

/**
 * Get string length
 * @param string $string The string being measured for length.
 * @return int<0,max> The length of the string on success, and 0 if the string is empty.
 */
function strlen(string $string): int {}

/**
 * Binary safe string comparison
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @return int less 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strcmp(string $string1, string $string2): int {}

/**
 * Binary safe string comparison of the first n characters
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @param int $length Number of characters to use in the comparison.
 * @return int less 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strncmp(string $string1, string $string2, int $length): int {}

/**
 * Binary safe case-insensitive string comparison
 * @param string $string1 The first string
 * @param string $string2 The second string
 * @return int less than 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strcasecmp(string $string1, string $string2): int {}

/**
 * Binary safe case-insensitive string comparison of the first n characters
 * @param string $string1 The first string.
 * @param string $string2 The second string.
 * @param int $length The length of strings to be used in the comparison.
 * @return int less than 0 if str1 is less than str2; > 0 if str1 is greater than str2, and 0 if they are equal.
 */
function strncasecmp(string $string1, string $string2, int $length): int {}

/**
 * The function returns true if the passed $haystack starts from the
 * $needle string or false otherwise.
 * @param string $haystack The string to search in.
 * @param string $needle The substring to search for in the haystack.
 * @return bool Returns true if haystack begins with needle, false otherwise.
 * @since 8.0
 */
function str_starts_with(string $haystack, string $needle): bool {}

/**
 * The function returns true if the passed $haystack ends with the
 * $needle string or false otherwise.
 * @param string $haystack The string to search in.
 * @param string $needle The substring to search for in the haystack.
 * @return bool Returns true if haystack ends with needle, false otherwise.
 * @since 8.0
 */
function str_ends_with(string $haystack, string $needle): bool {}

/**
 * Checks if $needle is found in $haystack and returns a boolean value
 * (true/false) whether or not the $needle was found.
 * @param string $haystack The string to search in.
 * @param string $needle The substring to search for in the haystack.
 * @return bool Returns true if needle is in haystack, false otherwise.
 * @since 8.0
 */
function str_contains(string $haystack, string $needle): bool {}

/**
 * Decrement an alphanumeric string
 *
 * Returns the decremented alphanumeric ASCII string.
 * @since 8.3
 * @throws \ValueError A ValueError is thrown if string is empty. A ValueError is thrown if string is not an alphanumeric ASCII string. A ValueError is thrown if string cannot be decremented. For example, "A" or "0".
 */
function str_decrement(string $string): string {}

/**
 * Increment an alphanumeric string
 *
 * Returns the incremented alphanumeric ASCII string.
 * @since 8.3
 * @throws \ValueError A ValueError is thrown if string is empty. A ValueError is thrown if string is not an alphanumeric ASCII string.
 */
function str_increment(string $string): string {}

/**
 * Return the current key and value pair from an array and advance the array cursor
 * @param array|ArrayObject &$array The input array.
 * @return array|false the current key and value pair from the array array. This pair is returned in a four-element array, with the keys 0, 1, key, and value. Elements 0 and key contain the key name of the array element, and 1 and value contain the data. If the internal pointer for the array points ...
 * @removed 8.0
 * @deprecated Use a foreach loop instead
 */
function each(&$array): array|false {}

/**
 * Sets which PHP errors are reported
 * @param int|null $error_level [optional] The new error_reporting level. It takes on either a bitmask, or named constants. Using named constants is strongly encouraged to ensure compatibility for future versions. As error levels are added, the range of integers increases, so older integer-based error ...
 * @return int the old error_reporting level or the current level if no level parameter is given.
 */
function error_reporting(?int $error_level = null): int {}

/**
 * Defines a named constant
 * @param string $constant_name The name of the constant.
 * @param null|array|bool|int|float|string $value The value of the constant. In PHP 5, value must be a scalar value (integer, float, string, boolean, or null). In PHP 7, array values are also accepted. It is possible to define resource constants, however it is not recommended and may cause ...
 * @param bool $case_insensitive [optional] If set to true, the constant will be defined case-insensitive. The default behavior is case-sensitive; i.e. CONSTANT and Constant represent different values. Defining case-insensitive constants is deprecated as of PHP 7.3.0. Case-insensitive constants are ...
 * @return bool true on success or false on failure.
 */
function define(
    string $constant_name,
    mixed $value,
    bool $case_insensitive = false
): bool {}

/**
 * Checks whether a given named constant exists
 * @param string $constant_name The constant name.
 * @return bool true if the named constant given by name has been defined, false otherwise.
 */
function defined(string $constant_name): bool {}

/**
 * Returns the name of the class of an object
 * @param object $object [optional] The tested object. This parameter may be omitted when inside a class.
 * @return string The name of the class of which object is an instance. If object is omitted when inside a class, the name of that class is returned.
 * @throws \TypeError If get_class is called with anything other than an object, TypeError is raised. Prior to PHP 8.0.0, an E_WARNING level error was raised.
 * @throws \Error If get_class is called with anything other than an object, TypeError is raised. Prior to PHP 8.0.0, an E_WARNING level error was raised. If get_class is called with no arguments from outside a class, an Error is thrown. Prior to PHP 8.0.0, an E_WARNING level error was raised.
 */
function get_class(object $object): string {}

/**
 * the "Late Static Binding" class name
 * @return string Returns the class name.
 * @throws \Error If get_called_class is called from outside a class, an Error is thrown. Prior to PHP 8.0.0, an E_WARNING level error was raised.
 */
function get_called_class(): string {}

/**
 * Retrieves the parent class name for object or class
 * @param object|string $object_or_class [optional] The tested object or class name
 * @return string|false The name of the parent class of the class of which object is an instance or the name. If the object does not have a parent false will be returned. If called without parameter outside object, this function returns false.
 */
function get_parent_class(object|string $object_or_class): string|false {}

/**
 * Checks if the class method exists
 * @param object|string $object_or_class An object instance or a class name
 * @param string $method The method name
 * @return bool true if the method given by method_name has been defined for the given object, false otherwise.
 */
function method_exists($object_or_class, string $method): bool {}

/**
 * Checks if the object or class has a property
 * @param object|string $object_or_class The class name or an object of the class to test for
 * @param string $property The name of the property
 * @return bool true if the property exists, false otherwise
 */
function property_exists($object_or_class, string $property): bool {}

/**
 * Checks if the trait exists
 * @param string $trait Name of the trait to check
 * @param bool $autoload [optional] Whether to autoload if not already loaded.
 * @return bool Returns true if trait exists, false otherwise
 * @since 5.4
 */
function trait_exists(string $trait, bool $autoload = true): bool {}

/**
 * Checks if the class has been defined
 * @param string $class The class name. The name is matched in a case-insensitive manner.
 * @param bool $autoload [optional] Whether or not to call autoload by default.
 * @return bool true if class_name is a defined class, false otherwise.
 */
function class_exists(string $class, bool $autoload = true): bool {}

/**
 * Checks if the interface has been defined
 * @param string $interface The interface name
 * @param bool $autoload [optional] Whether to call autoload or not by default.
 * @return bool true if the interface given by interface_name has been defined, false otherwise.
 * @since 5.0
 */
function interface_exists(string $interface, bool $autoload = true): bool {}

/**
 * Return true if the given function has been defined
 * @param string $function The function name, as a string.
 * @return bool true if function_name exists and is a function, false otherwise. This function will return false for constructs, such as include_once and echo.
 */
function function_exists(string $function): bool {}

/**
 * Checks if the enum has been defined
 * @param string $enum The enum name. The name is matched in a case-insensitive manner.
 * @param bool $autoload [optional] Whether or not to call autoload by default.
 * @return bool true if enum is a defined enum, false otherwise.
 * @since 8.1
 */
function enum_exists(string $enum, bool $autoload = true): bool {}

/**
 * Creates an alias for a class
 * @param string $class The original class.
 * @param string $alias The alias name for the class.
 * @param bool $autoload [optional] Whether to autoload if the original class is not found.
 * @return bool true on success or false on failure.
 */
function class_alias(string $class, string $alias, bool $autoload = true): bool {}

/**
 * Returns an array with the names of included or required files
 * @return string[] an array of the names of all files. The script originally called is considered an "included file," so it will be listed together with the files referenced by include and family. Files that are included or required multiple times only show up once in the returned array.
 */
function get_included_files(): array {}

/**
 * Alias of get_included_files
 * @return string[]
 */
function get_required_files(): array {}

/**
 * checks if the object has this class as one of its parents or implements it
 * @param object|string $object_or_class A class name or an object instance
 * @param string $class The class name
 * @param bool $allow_string [optional] If this parameter set to false, string class name as object is not allowed. This also prevents from calling autoloader if the class doesn't exist.
 * @return bool This function returns true if the object object, belongs to a class which is a subclass of class_name, false otherwise.
 */
function is_subclass_of(mixed $object_or_class, string $class, bool $allow_string = true): bool {}

/**
 * Checks if the object is of this class or has this class as one of its parents
 * @param object|string $object_or_class The tested object
 * @param string $class The class name
 * @param bool $allow_string [optional] If this parameter set to FALSE, string class name as object is not allowed. This also prevents from calling autoloader if the class doesn't exist.
 * @return bool TRUE if the object is of this class or has this class as one of its parents, FALSE otherwise.
 */
function is_a(mixed $object_or_class, string $class, bool $allow_string = false): bool {}

/**
 * Get the default properties of the class
 * @param string $class The class name
 * @return array an associative array of declared properties visible from the current scope, with their default value. The resulting array elements are in the form of varname => value.
 */
function get_class_vars(string $class): array {}

/**
 * Gets the properties of the given object
 * @param object $object An object instance.
 * @return array an associative array of defined object accessible non-static properties for the specified object in scope. If a property have not been assigned a value, it will be returned with a null value.
 */
function get_object_vars(object $object): array {}

/**
 * Gets the class methods' names
 * @param object|string $object_or_class The class name or an object instance
 * @return string[] an array of method names defined for the class specified by class_name. Prior to PHP 8.0, passing a value that was neither an object nor a class name raised a warning and returned null; since 8.0 a TypeError is thrown instead.
 */
function get_class_methods(object|string $object_or_class): array {}

/**
 * Generates a user-level error/warning/notice message
 * @param string $message The designated error message for this error. It's limited to 1024 characters in length. Any additional characters beyond 1024 will be truncated.
 * @param int $error_level [optional] The designated error type for this error. It only works with the E_USER family of constants, and will default to E_USER_NOTICE.
 * @return bool This function returns false if wrong error_type is specified, true otherwise.
 * @throws \ValueError This function throws a ValueError if error_level is not one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, E_USER_DEPRECATED.
 */
function trigger_error(string $message, int $error_level = E_USER_NOTICE): bool {}

/**
 * Alias of trigger_error
 * @param string $message
 * @param int $error_level [optional]
 * @return bool This function returns false if wrong error_type is specified, true otherwise.
 */
function user_error(string $message, int $error_level = E_USER_NOTICE): bool {}

/**
 * Sets a user-defined error handler function
 * @param callable|null $callback The user function needs to accept two parameters: the error code, and a string describing the error. Then there are three optional parameters that may be supplied: the filename in which the error occurred, the line number in which the error occurred, and the context ...
 * @param int $error_levels [optional] Can be used to mask the triggering of the error_handler function just like the error_reporting ini setting controls which errors are shown. Without this mask set the error_handler will be called for every error regardless to the setting of the error_reporting ...
 * @return callable|null a string containing the previously defined error handler (if any). If the built-in error handler is used null is returned. null is also returned in case of an error such as an invalid callback. If the previous error handler was a class method, this function will return an ...
 */
function set_error_handler(?callable $callback, int $error_levels = E_ALL) {}

/**
 * Restores the previous error handler function
 * @return bool This function always returns true.
 */
function restore_error_handler(): true {}

/**
 * Gets the user-defined error handler function
 *
 * Returns the current error handler function, if any.
 * @since 8.5
 */
function get_error_handler(): ?callable {}

/**
 * Sets a user-defined exception handler function
 * @param callable|null $callback Name of the function to be called when an uncaught exception occurs. This function must be defined before calling set_exception_handler. This handler function needs to accept one parameter, which will be the exception object that was thrown. NULL may be passed ...
 * @return callable|null the name of the previously defined exception handler, or null on error. If no previous handler was defined, null is also returned.
 */
function set_exception_handler(?callable $callback) {}

/**
 * Gets the user-defined exception handler function
 *
 * Returns the current exception handler function, if any.
 * @since 8.5
 */
function get_exception_handler(): ?callable {}

/**
 * Restores the previously defined exception handler function
 * @return bool This function always returns true.
 */
function restore_exception_handler(): true {}

/**
 * Returns an array with the name of the defined classes
 * @return string[] an array of the names of the declared classes in the current script. Note that depending on what extensions you have compiled or loaded into PHP, additional classes could be present. This means that you will not be able to define your own classes using these names. There is a list ...
 */
function get_declared_classes(): array {}

/**
 * Returns an array of all declared interfaces
 * @return string[] an array of the names of the declared interfaces in the current script.
 */
function get_declared_interfaces(): array {}

/**
 * Returns an array of all declared traits
 * @return array with names of all declared traits in values.
 * @see class_uses()
 * @since 5.4
 */
function get_declared_traits(): array {}

/**
 * Returns an array of all defined functions
 * @param bool $exclude_disabled [optional] Whether disabled functions should be excluded from the return value.
 * @return array an multidimensional array containing a list of all defined functions, both built-in (internal) and user-defined. The internal functions will be accessible via $arr["internal"], and the user defined ones using $arr["user"] (see example below).
 */
function get_defined_functions(bool $exclude_disabled = true): array {}

/**
 * Returns an array of all defined variables
 * @return array A multidimensional array with all the variables.
 */
function get_defined_vars(): array {}

/**
 * Create an anonymous (lambda-style) function
 * @param string $args The function arguments.
 * @param string $code The function code.
 * @return string|false a unique function name as a string, or false on error.
 * @removed 8.0
 * @deprecated Use anonymous functions instead
 */
function create_function(string $args, string $code): false|string {}

/**
 * Returns the resource type
 * @param resource $resource The evaluated resource handle.
 * @return string If the given handle is a resource, this function will return a string representing its type. If the type is not identified by this function, the return value will be the string Unknown.
 */
function get_resource_type($resource): string {}

/**
 * Returns an array with the names of all modules compiled and loaded
 * @param bool $zend_extensions [optional] Only return Zend extensions, if not then regular extensions, like mysqli are listed. Defaults to false (return regular extensions).
 * @return string[] an indexed array of all the modules names.
 */
function get_loaded_extensions(bool $zend_extensions = false): array {}

/**
 * Find out whether an extension is loaded
 * @param string $extension The extension name. You can see the names of various extensions by using phpinfo or if you're using the CGI or CLI version of PHP you can use the -m switch to list all available extensions: $ php -m [PHP Modules] xml tokenizer standard sockets session posix pcre overload ...
 * @return bool true if the extension identified by name is loaded, false otherwise.
 */
function extension_loaded(string $extension): bool {}

/**
 * Returns an array with the names of the functions of a module
 * @param string $extension The module name. This parameter must be in lowercase.
 * @return string[]|false an array with all the functions, or false if module_name is not a valid extension.
 */
function get_extension_funcs(string $extension): array|false {}

/**
 * Returns an associative array with the names of all the constants and their values
 * @param bool $categorize [optional] Causing this function to return a multi-dimensional array with categories in the keys of the first dimension and constants and their values in the second dimension. define("MY_CONSTANT", 1); print_r(get_defined_constants(true)); The above example will output ...
 * @return array Returns an array of constant name => constant value array, optionally grouped by extension name registering the constant.
 */
function get_defined_constants(bool $categorize = false): array {}

/**
 * Generates a backtrace
 * @param int $options [optional] As of 5.3.6, this parameter is a bitmask for the following options: debug_backtrace options DEBUG_BACKTRACE_PROVIDE_OBJECT Whether or not to populate the "object" index. DEBUG_BACKTRACE_IGNORE_ARGS Whether or not to omit the "args" index, and thus all the ...
 * @param int $limit [optional] As of 5.4.0, this parameter can be used to limit the number of stack frames returned. By default (limit=0) it returns all stack frames.
 * @return array an array of associative arrays. The possible returned elements are as follows: Possible returned elements from debug_backtrace Name Type Description function string The current function name. See also __FUNCTION__. line integer The current line number. See also __LINE__. file string ...
 */
function debug_backtrace(int $options = DEBUG_BACKTRACE_PROVIDE_OBJECT, int $limit = 0): array {}

/**
 * Prints a backtrace
 * @param int $options [optional] As of 5.3.6, this parameter is a bitmask for the following options: debug_print_backtrace options DEBUG_BACKTRACE_IGNORE_ARGS Whether or not to omit the "args" index, and thus all the function/method arguments, to save memory.
 * @param int $limit [optional] As of 5.4.0, this parameter can be used to limit the number of stack frames printed. By default (limit = 0) it prints all stack frames.
 * @return void No value is returned.
 */
function debug_print_backtrace(
    int $options = 0,
    int $limit = 0
): void {}

/**
 * Forces collection of any existing garbage cycles
 * @return int number of collected cycles.
 */
function gc_collect_cycles(): int {}

/**
 * Returns status of the circular reference collector
 * @return bool true if the garbage collector is enabled, false otherwise.
 */
function gc_enabled(): bool {}

/**
 * Activates the circular reference collector
 * @return void No value is returned.
 */
function gc_enable(): void {}

/**
 * Deactivates the circular reference collector
 * @return void No value is returned.
 */
function gc_disable(): void {}

/**
 * Gets information about the garbage collector
 * @return int[] associative array with the following elements: "runs" "collected" "threshold" "roots"
 * @since 7.3
 */
function gc_status(): array {}

/**
 * Reclaims memory used by the Zend Engine memory manager
 * @return int Returns the number of bytes freed.
 * @since 7.0
 */
function gc_mem_caches(): int {}

/**
 * Returns active resources
 * @param string|null $type [optional] If defined, this will cause get_resources() to only return resources of the given type. A list of resource types is available. If the string Unknown is provided as the type, then only resources that are of an unknown type will be returned. If omitted, all ...
 * @return resource[] Returns an array of currently active resources, indexed by resource number.
 * @since 7.0
 */
function get_resources(?string $type = null): array {}

/**
 * Terminate the current script with a status code or message
 *
 * Terminates execution of the script. Shutdown functions and object destructors will always be
 * executed even if exit is called. However, finally blocks are never executed.
 * @since 8.4
 */
function exit(string|int $status = 0): never {}

/**
 * @since 8.4
 */
function die(string|int $status = 0): never {}

/**
 * @template TObject of object
 * @param TObject $object
 * @param array $withProperties [optional]
 * @return TObject
 * @since 8.5
 */
function clone(object $object, array $withProperties = []): object {}
