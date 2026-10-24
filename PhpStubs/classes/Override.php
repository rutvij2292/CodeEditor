<?php

/**
 * This attribute is used to indicate that a method or a property is intended to override a method
 * or a property of a parent class or that it implements a method or a property defined in an
 * interface.
 *
 * If no method or property with the same name exists in a parent class or in an implemented
 * interface a compile-time error will be emitted. The attribute cannot be used on the __construct()
 * method, which is exempt from signature checks.
 * @since 8.3
 */
final class Override
{
    /**
     * Construct a new Override attribute instance
     *
     * Constructs a new Override instance.
     */
    public function __construct() {}
}
