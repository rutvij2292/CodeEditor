<?php
namespace Random;

use Error;
use Exception;

/**
 * @since 8.3
 */
enum IntervalBoundary implements \UnitEnum
{
    public string $name;

    case ClosedOpen;

    case ClosedClosed;

    case OpenClosed;

    case OpenOpen;

    public static function cases(): array {}
}
