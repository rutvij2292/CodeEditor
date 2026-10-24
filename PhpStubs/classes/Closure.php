<?php

/**
 * Class used to represent anonymous functions.
 * Anonymous functions, implemented in PHP 5.3, yield objects of this type.
 * This fact used to be considered an implementation detail, but it can now be relied upon.
 * Starting with PHP 5.4, this class has methods that allow further control of the anonymous function after it has been created.
 * Besides the methods listed here, this class also has an __invoke method.
 * This is for consistency with other classes that implement calling magic, as this method is not used for calling the function.
 */
final class Closure
{
    /**
     * This method exists only to disallow instantiation of the Closure class.
     * Objects of this class are created in the fashion described on the anonymous functions page.
     */
    private function __construct() {}

    /**
     * This is for consistency with other classes that implement calling magic,
     * as this method is not used for calling the function.
     * @param mixed ...$_ [optional]
     * @return mixed
     */
    public function __invoke(...$_) {}

    /**
     * Duplicates the closure with a new bound object and class scope
     * @param object|null $newThis The object to which the given anonymous function should be bound, or NULL for the closure to be unbound.
     * @param object|class-string|null $newScope The class scope to which associate the closure is to be associated, or 'static' to keep the current one. If an object is given, the type of the object will be used instead. This determines the visibility of protected and private methods of the bound object.
     * @return Closure|null Returns the newly created Closure object or null on failure
     */
    public function bindTo(?object $newThis, object|string|null $newScope = 'static'): ?Closure {}

    /**
     * This method is a static version of Closure::bindTo().
     * See the documentation of that method for more information.
     * @param Closure $closure The anonymous functions to bind.
     * @param object|null $newThis The object to which the given anonymous function should be bound, or NULL for the closure to be unbound.
     * @param object|class-string|null $newScope The class scope to which associate the closure is to be associated, or 'static' to keep the current one. If an object is given, the type of the object will be used instead. This determines the visibility of protected and private methods of the bound object.
     * @return Closure|null Returns the newly created Closure object or null on failure
     */
    public static function bind(Closure $closure, ?object $newThis, object|string|null $newScope = 'static'): ?Closure {}

    /**
     * Temporarily binds the closure to newthis, and calls it with any given parameters.
     * @param object $newThis The object to bind the closure to for the duration of the call.
     * @param mixed $args [optional] Zero or more parameters, which will be given as parameters to the closure.
     * @return mixed Returns the return value of the closure.
     * @since 7.0
     */
    public function call(object $newThis, mixed ...$args): mixed {}

    /**
     * Converts a callable into a closure
     *
     * Create and return a new anonymous function from given callback using the current scope. This
     * method checks if the callback is callable in the current scope and throws a TypeError if it
     * is not.
     * @param callable $callback The callable to convert.
     * @return Closure Returns the newly created Closure or throws a TypeError if the callback is not callable in the current scope.
     * @since 7.1
     */
    public static function fromCallable(callable $callback): Closure {}

    /**
     * Returns the currently executing closure
     *
     * Returns the currently executing closure. This method is primarily useful for implementing
     * recursive closures without needing to capture a reference to the closure variable using the
     * use keyword.
     * @since 8.5
     * @throws \Error Throws an Error if called outside of a closure context.
     */
    public static function getCurrent(): Closure {}
}
