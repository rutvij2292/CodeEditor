<?php

/**
 * DOM operations raise exceptions under particular circumstances, i.e.,
 * when an operation is impossible to perform for logical reasons.
 */
final class DOMException extends Exception
{
    /**
     * @var int An integer indicating the type of error generated
     */
    public $code;
}
