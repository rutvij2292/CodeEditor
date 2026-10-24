<?php

/**
 * @since 8.6
 */
enum StreamErrorMode implements \UnitEnum
{
    case Error;

    case Exception;

    case Silent;
}
