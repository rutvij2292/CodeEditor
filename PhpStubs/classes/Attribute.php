<?php

/**
 * Attributes offer the ability to add structured, machine-readable metadata information on
 * declarations in code: Classes, methods, functions, parameters, properties and class constants can
 * be the target of an attribute. The metadata defined by attributes can then be inspected at
 * runtime using the Reflection APIs. Attributes could therefore be thought of as a configuration
 * language embedded directly into code.
 * @since 8.0
 */
final class Attribute
{
    public int $flags;

    /**
     * Marks that attribute declaration is allowed only in classes.
     */
    public const TARGET_CLASS = 1;

    /**
     * Marks that attribute declaration is allowed only in functions.
     */
    public const TARGET_FUNCTION = 2;

    /**
     * Marks that attribute declaration is allowed only in class methods.
     */
    public const TARGET_METHOD = 4;

    /**
     * Marks that attribute declaration is allowed only in class properties.
     */
    public const TARGET_PROPERTY = 8;

    /**
     * Marks that attribute declaration is allowed only in class constants.
     */
    public const TARGET_CLASS_CONSTANT = 16;

    /**
     * Marks that attribute declaration is allowed only in function or method parameters.
     */
    public const TARGET_PARAMETER = 32;

    /**
     * Marks that attribute declaration is allowed only in constants.
     * @since 8.5
     */
    public const TARGET_CONSTANT = 64;

    /**
     * Marks that attribute declaration is allowed anywhere.
     */
    public const TARGET_ALL = 127;

    /**
     * Notes that an attribute declaration in the same place is
     * allowed multiple times.
     */
    public const IS_REPEATABLE = 128;

    /**
     * Construct a new Attribute instance
     *
     * Constructs a new Attribute instance.
     * @param int $flags A value in the form of a bitmask indicating the places where attributes can be defined.
     */
    public function __construct(int $flags = Attribute::TARGET_ALL) {}
}
