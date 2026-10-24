<?php

/**
 * As of PHP 8.1.0, a tentative phase of transitioning to return type declarations for internal
 * class methods began.
 *
 * Most non-final internal methods now require overriding methods to declare a compatible return
 * type. Otherwise, a deprecation notice is emitted during inheritance validation warning that the
 * signature violates covariance rules. In a future PHP version, method signature checking will
 * become strict, and mismatches will cause a fatal error. In case the return type cannot be
 * declared for an overriding method due to PHP cross-version compatibility concerns, or the
 * overriding method declares an incompatible return type, a #[\ReturnTypeWillChange] attribute can
 * be added to silence the ...
 * @since 8.1
 */
final class ReturnTypeWillChange
{
    /**
     * Construct a new ReturnTypeWillChange attribute instance
     *
     * Constructs a new ReturnTypeWillChange instance.
     */
    public function __construct() {}
}
