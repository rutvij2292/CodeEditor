<?php

/**
 * Representation of date interval. A date interval stores either a fixed amount of
 * time (in years, months, days, hours etc) or a relative time string in the format
 * that DateTime's constructor supports.
 */
class DateInterval
{
    /**
     * Number of years
     * @var int
     */
    public $y;

    /**
     * Number of months
     * @var int
     */
    public $m;

    /**
     * Number of days
     * @var int
     */
    public $d;

    /**
     * Number of hours
     * @var int
     */
    public $h;

    /**
     * Number of minutes
     * @var int
     */
    public $i;

    /**
     * Number of seconds
     * @var int
     */
    public $s;

    /**
     * Number of microseconds
     * @since 7.1.0
     * @var float
     */
    public $f;

    /**
     * Is 1 if the interval is inverted and 0 otherwise
     * @var int
     */
    public $invert;

    /**
     * Total number of days the interval spans. If this is unknown, days will be FALSE.
     * @var int|false
     */
    public $days;

    /**
     * Creates a new DateInterval object
     * @param string $duration An interval specification. The format starts with the letter P, for period. Each duration period is represented by an integer value followed by a period designator. If the duration contains time elements, that portion of the specification is preceded by the letter T. ...
     * @throws DateMalformedIntervalStringException when the $duration cannot be parsed as an interval.
     */
    public function __construct(string $duration) {}

    /**
     * Formats the interval
     * @param string $format The following characters are recognized in the format parameter string. Each format character must be prefixed by a percent sign (%). format character Description Example values % Literal % % Y Years, numeric, at least 2 digits with leading 0 01, 03 y Years, numeric 1, 3 M ...
     * @return string Returns the formatted interval.
     */
    public function format(string $format): string {}

    /**
     * Sets up a DateInterval from the relative parts of the string
     * @param string $datetime A date with relative parts. Specifically, the relative formats supported by the parser used for DateTimeImmutable, DateTime, and strtotime will be used to construct the DateInterval. To use an ISO-8601 format string like P7D, you must use the DateInterval::__construct.
     * @return DateInterval|false Returns a new DateInterval instance on success, or FALSE on failure.
     * @throws DateMalformedIntervalStringException
     */
    public static function createFromDateString(string $datetime): DateInterval|false {}

    public function __wakeup(): void {}

    public static function __set_state(array $array): static {}

    public function __serialize(): array {}

    public function __unserialize(array $data): void {}
}
