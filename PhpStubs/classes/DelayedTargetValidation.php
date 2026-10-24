<?php

/**
 * This attribute delays target validation errors for internal attributes from compile time to when
 * the attribute is instantiated via the Reflection API.
 *
 * When applied to a declaration, any invalid usage of internal attributes on the same target will
 * not trigger a compile time error. Instead, the validation is deferred and performed when the
 * attribute is instantiated via ReflectionAttribute::newInstance(). This is primarily intended for
 * forward compatibility, allowing code to use attributes that may gain additional valid targets in
 * future PHP versions without breaking on older versions.
 * @since 8.5
 */
final class DelayedTargetValidation
{

}
