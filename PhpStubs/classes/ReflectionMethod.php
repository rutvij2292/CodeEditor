<?php

/**
 * The ReflectionMethod class reports
 * information about a method.
 */
class ReflectionMethod extends ReflectionFunctionAbstract
{
    /**
     * @var string Name of the method, same as calling the ReflectionMethod::getName() method
     */
    public string $name;

    /**
     * @var class-string Fully qualified class name where this method was defined
     */
    public string $class;

    /**
     * Indicates that the method is static.
     */
    public const IS_STATIC = 16;

    /**
     * Indicates that the method is public.
     */
    public const IS_PUBLIC = 1;

    /**
     * Indicates that the method is protected.
     */
    public const IS_PROTECTED = 2;

    /**
     * Indicates that the method is private.
     */
    public const IS_PRIVATE = 4;

    /**
     * Indicates that the method is abstract.
     */
    public const IS_ABSTRACT = 64;

    /**
     * Indicates that the method is final.
     */
    public const IS_FINAL = 32;

    /**
     * Constructs a ReflectionMethod
     *
     * $reflection = new ReflectionMethod(new Example(), 'method');
     * $reflection = new ReflectionMethod(Example::class, 'method');
     * $reflection = new ReflectionMethod('Example::method');
     * @param string|object $objectOrMethod Classname, object (instance of the class) that contains the method or class name and method name delimited by ::.
     * @param string|null $method Name of the method if the first argument is a classname or an object.
     * @throws ReflectionException if the class or method does not exist.
     */
    public function __construct(
        object|string $objectOrMethod,
        string|null $method = null
    ) {}

    /**
     * Export a reflection method.
     * @param string $class The class name.
     * @param string $name The name of the method.
     * @param bool $return Setting to true will return the export, as opposed to emitting it. Setting to false (the default) will do the opposite.
     * @return string|null If the $return parameter is set to true, then the export is returned as a string, otherwise null is returned.
     * @removed 8.0
     * @deprecated
     */
    public static function export($class, $name, $return = false) {}

    /**
     * Returns the string representation of the ReflectionMethod object.
     * @return string A string representation of this ReflectionMethod instance.
     */
    public function __toString(): string {}

    /**
     * Checks if method is public
     * @return bool Returns true if the method is public, otherwise false
     */
    public function isPublic(): bool {}

    /**
     * Checks if method is private
     * @return bool Returns true if the method is private, otherwise false
     */
    public function isPrivate(): bool {}

    /**
     * Checks if method is protected
     * @return bool Returns true if the method is protected, otherwise false
     */
    public function isProtected(): bool {}

    /**
     * Checks if method is abstract
     * @return bool Returns true if the method is abstract, otherwise false
     */
    public function isAbstract(): bool {}

    /**
     * Checks if method is final
     * @return bool Returns true if the method is final, otherwise false
     */
    public function isFinal(): bool {}

    /**
     * Checks if method is static
     * @return bool Returns true if the method is static, otherwise false
     */
    public function isStatic(): bool {}

    /**
     * Checks if method is a constructor
     * @return bool Returns true if the method is a constructor, otherwise false
     */
    public function isConstructor(): bool {}

    /**
     * Checks if method is a destructor
     * @return bool Returns true if the method is a destructor, otherwise false
     */
    public function isDestructor(): bool {}

    /**
     * Returns a dynamically created closure for the method
     * @param object|null $object Forbidden for static methods, required for other methods or nothing.
     * @return Closure Returns the newly created Closure.
     * @throws ValueError if object is null but the method is non-static.
     * @throws ReflectionException if object is not an instance of the class this method was declared in.
     * @since 5.4
     */
    public function getClosure(
        object|null $object = null
    ): Closure {}

    /**
     * Gets the method modifiers
     * @return int A numeric representation of the modifiers. The modifiers are listed below. The actual meanings of these modifiers are described in the predefined constants. ReflectionMethod modifiers: - ReflectionMethod::IS_STATIC - Indicates that the method is static. - ReflectionMethod::IS_PUBLIC - ...
     */
    public function getModifiers(): int {}

    /**
     * Invokes a reflected method.
     * @param object|null $object The object to invoke the method on. For static methods, pass null to this parameter.
     * @param mixed ...$args Zero or more parameters to be passed to the method. It accepts a variable number of parameters which are passed to the method.
     * @return mixed Returns the method result.
     * @throws ReflectionException if the object parameter does not contain an instance of the class that this method was declared in or the method invocation failed.
     */
    public function invoke(
        object|null $object,
        mixed ...$args
    ): mixed {}

    /**
     * Invokes the reflected method and pass its arguments as array.
     * @param object|null $object The object to invoke the method on. In case of static methods, you can pass null to this parameter.
     * @param array $args The parameters to be passed to the function, as an array.
     * @return mixed the method result.
     * @throws ReflectionException if the object parameter does not contain an instance of the class that this method was declared in or the method invocation failed.
     */
    public function invokeArgs(object|null $object, array $args): mixed {}

    /**
     * Gets declaring class for the reflected method.
     * @return ReflectionClass A ReflectionClass object of the class that the reflected method is part of.
     */
    public function getDeclaringClass(): ReflectionClass {}

    /**
     * Gets the method prototype (if there is one).
     * @return ReflectionMethod A ReflectionMethod instance of the method prototype.
     * @throws ReflectionException if the method does not have a prototype
     */
    public function getPrototype(): ReflectionMethod {}

    /**
     * Set method accessibility
     * This method is no-op starting from PHP 8.1
     * @param bool $accessible true to allow accessibility, or false
     * @return void No value is returned.
     */
    public function setAccessible(bool $accessible): void {}

    /**
     * Returns whether a method has a prototype
     * @return bool Returns true if the method has a prototype, otherwise false.
     */
    public function hasPrototype(): bool {}

    /**
     * Creates a new ReflectionMethod
     * @since 8.3
     * @throws \ReflectionException A ReflectionException is thrown if the given method does not exist.
     */
    public static function createFromMethodName(string $method): static {}
}
