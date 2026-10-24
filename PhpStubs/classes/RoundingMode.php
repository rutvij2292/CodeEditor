<?php

/**
 * @since 8.4
 */
enum RoundingMode implements \UnitEnum
{
    case HalfAwayFromZero;

    case HalfTowardsZero;

    case HalfEven;

    case HalfOdd;

    case TowardsZero;

    case AwayFromZero;

    case NegativeInfinity;

    case PositiveInfinity;

    public static function cases(): array {}
}
