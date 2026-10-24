<?php

/**
 * Created by unserialize when trying to unserialize an undefined class or a class that is not
 * listed in the allowed_classes of unserialize's options array.
 *
 * Prior to PHP 7.2.0, using is_object on the __PHP_Incomplete_Class class would return false. As of
 * PHP 7.2.0, true will be returned.
 */
final class __PHP_Incomplete_Class
{
    /**
     * @var string
     */
    public $__PHP_Incomplete_Class_Name;
}
