<?php

/**
 * Return available SPL classes
 * @return array Returns an array containing the currently available SPL classes.
 */
function spl_classes(): array {}

/**
 * Default implementation for __autoload()
 * @param string $class
 * @param string|null $file_extensions [optional] By default it checks all include paths to contain filenames built up by the lowercase class name appended by the filename extensions .inc and .php.
 * @return void No value is returned.
 * @since 5.1
 * @throws \LogicException Throws LogicException when the class is not found and there are no other autoloaders registered.
 */
function spl_autoload(string $class, ?string $file_extensions = null): void {}

/**
 * Register and return default file extensions for spl_autoload
 * @param string|null $file_extensions [optional] When calling without an argument, it simply returns the current list of extensions each separated by comma. To modify the list of file extensions, simply invoke the functions with the new list of file extensions to use in a single string with each ...
 * @return string A comma delimited list of default file extensions for spl_autoload.
 * @since 5.1
 */
function spl_autoload_extensions(?string $file_extensions = null): string {}

/**
 * Register given function as __autoload() implementation
 * @param callable|null $callback [optional] The autoload function being registered. If no parameter is provided, then the default implementation of spl_autoload will be registered.
 * @param bool $throw This parameter specifies whether spl_autoload_register() should throw exceptions when the autoload_function cannot be registered. Ignored since since 8.0.
 * @param bool $prepend If true, spl_autoload_register() will prepend the autoloader on the autoload stack instead of appending it.
 * @return bool true on success or false on failure.
 * @throws TypeError Since 8.0.
 * @since 5.1
 */
function spl_autoload_register(?callable $callback = null, bool $throw = true, bool $prepend = false): bool {}

/**
 * Unregister given function as __autoload() implementation
 * @param callable $callback The autoload function being unregistered.
 * @return bool true on success or false on failure.
 * @since 5.1
 */
function spl_autoload_unregister(callable $callback): bool {}

/**
 * Return all registered __autoload() functions
 * @return array|false An array of all registered __autoload functions. If the autoload stack is not activated then the return value is false. If no function is registered the return value will be an empty array.
 * @since 5.1
 */
function spl_autoload_functions(): array {}

/**
 * Try all registered __autoload() functions to load the requested class
 * @param string $class The class name being searched.
 * @return void No value is returned.
 * @since 5.1
 */
function spl_autoload_call(string $class): void {}

/**
 * Return the parent classes of the given class
 * @param object|string $object_or_class An object (class instance) or a string (class name).
 * @param bool $autoload [optional] Whether to allow this function to load the class automatically through the __autoload magic method.
 * @return string[]|false An array on success, or false on error.
 */
function class_parents($object_or_class, bool $autoload = true): array|false {}

/**
 * Return the interfaces which are implemented by the given class
 * @param object|string $object_or_class An object (class instance) or a string (class name).
 * @param bool $autoload [optional] Whether to allow this function to load the class automatically through the __autoload magic method.
 * @return string[]|false An array on success, or false on error.
 */
function class_implements($object_or_class, bool $autoload = true): array|false {}

/**
 * Return hash id for given object
 * @param object $object Any object.
 * @return string A string that is unique for each object and is always the same for the same object.
 */
function spl_object_hash(object $object): string {}

/**
 * Copy the iterator into an array
 * @template TKey of int|string
 * @template TValue
 * @param Traversable<TKey, TValue>|array<TKey, TValue> $iterator The iterator being copied.
 * @param bool $preserve_keys [optional] Whether to use the iterator element keys as index.
 * @return ( $preserve_keys is true ? array<TKey, TValue> : ( $preserve_keys is false ? TValue[] : array<TKey, TValue>|TValue[]) ) An array containing the elements of the iterator.
 */
function iterator_to_array(Traversable|array $iterator, bool $preserve_keys = true): array {}

/**
 * Count the elements in an iterator
 * @param Traversable $iterator The iterator being counted.
 * @return int The number of elements in iterator.
 */
function iterator_count(Traversable|array $iterator): int {}

/**
 * Call a function for every element in an iterator
 * @param Traversable $iterator The class to iterate over.
 * @param callable $callback The callback function to call on every element. The function must return true in order to continue iterating over the iterator.
 * @param array|null $args [optional] Arguments to pass to the callback function.
 * @return int the iteration count.
 */
function iterator_apply(Traversable $iterator, callable $callback, ?array $args = null): int {}

/**
 * Return the traits used by the given class
 * @param object|string $object_or_class An object (class instance) or a string (class name).
 * @param bool $autoload Whether to allow this function to load the class automatically through the __autoload() magic method.
 * @return string[]|false An array on success, or false on error.
 * @see class_parents()
 * @see get_declared_traits()
 * @since 5.4
 */
function class_uses($object_or_class, bool $autoload = true): array|false {}

/**
 * return the integer object handle for given object
 * @param object $object Any object.
 * @return int An integer identifier that is unique for each currently existing object and is always the same for each object.
 * @since 7.2
 */
function spl_object_id(object $object): int {}
