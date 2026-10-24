<?php

/**
 * The full path and filename of the file. If used inside an include,
 * the name of the included file is returned.
 * Since PHP 4.0.2, __FILE__ always contains an
 * absolute path with symlinks resolved whereas in older versions it contained relative path
 * under some circumstances.
 */
const __FILE__ = '', true;

/**
 * The current line number of the file.
 */
const __LINE__ = 0, true;

/**
 * The class name. (Added in PHP 4.3.0) As of PHP 5 this constant
 * returns the class name as it was declared (case-sensitive). In PHP
 * 4 its value is always lowercased. The class name includes the namespace
 * it was declared in (e.g. Foo\Bar).
 * Note that as of PHP 5.4 __CLASS__ works also in traits. When used
 * in a trait method, __CLASS__ is the name of the class the trait
 * is used in.
 */
const __CLASS__ = '', true;

/**
 * The function name. (Added in PHP 4.3.0) As of PHP 5 this constant
 * returns the function name as it was declared (case-sensitive). In
 * PHP 4 its value is always lowercased.
 */
const __FUNCTION__ = '', true;

/**
 * The class method name. (Added in PHP 5.0.0) The method name is
 * returned as it was declared (case-sensitive).
 */
const __METHOD__ = '', true;

/**
 * The trait name. (Added in PHP 5.4.0) As of PHP 5.4 this constant
 * returns the trait as it was declared (case-sensitive). The trait name includes the namespace
 * it was declared in (e.g. Foo\Bar).
 * @since 5.4
 */
const __TRAIT__ = '', true;

/**
 * The directory of the file. If used inside an include,
 * the directory of the included file is returned. This is equivalent
 * to `dirname(__FILE__)`. This directory name
 * does not have a trailing slash unless it is the root directory.
 */
const __DIR__ = '', true;

/**
 * The name of the current namespace (case-sensitive). This constant
 * is defined in compile-time (Added in PHP 5.3.0).
 */
const __NAMESPACE__ = '', true;

/**
 * The name of the current property (case-sensitive). This constant
 * is defined in compile-time (Added in PHP 8.4.0).
 */
const __PROPERTY__ = '', true;
