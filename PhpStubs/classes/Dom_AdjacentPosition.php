<?php
namespace Dom;

/**
 * @since 8.4
 */
enum AdjacentPosition implements \BackedEnum, \UnitEnum
{
    case BeforeBegin = "beforebegin";

    case AfterBegin = "afterbegin";

    case BeforeEnd = "beforeend";

    case AfterEnd = "afterend";

    public static function cases(): array {}

    public static function from(string|int $value): static {}

    public static function tryFrom(string|int $value): ?static {}
}
