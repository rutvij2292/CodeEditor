<?php

/**
 * Representation of date period.
 * @template TDate of DateTimeInterface
 * @template TEnd of ?DateTimeInterface
 * @implements \IteratorAggregate<int, TDate>
 */
class DatePeriod implements IteratorAggregate
{
    public const EXCLUDE_START_DATE = 1;

    /**
     * @since 8.2
     */
    public const INCLUDE_END_DATE = 2;

    /**
     * Start date
     * @var DateTimeInterface
     */
    public DateTimeInterface|null $start;

    /**
     * Current iterator value.
     * @var DateTimeInterface|null
     */
    public DateTimeInterface|null $current;

    /**
     * End date.
     * @var DateTimeInterface|null
     */
    public DateTimeInterface|null $end;

    /**
     * The interval
     * @var DateInterval
     */
    public DateInterval|null $interval;

    /**
     * Number of recurrences.
     * @var int
     */
    public int $recurrences;

    /**
     * Start of period.
     * @var bool
     */
    public bool $include_start_date;

    /**
     * @since 8.2
     */
    public bool $include_end_date;

    /**
     * @param TDate $start
     * @param DateInterval $interval
     * @param TEnd $end
     * @param int $options Can be set to DatePeriod::EXCLUDE_START_DATE.
     */
    public function __construct(DateTimeInterface $start, DateInterval $interval, DateTimeInterface $end, $options = 0) {}

    /**
     * @param TDate $start
     * @param DateInterval $interval
     * @param int $recurrences Number of recurrences
     * @param int $options Can be set to DatePeriod::EXCLUDE_START_DATE.
     */
    public function __construct(DateTimeInterface $start, DateInterval $interval, $recurrences, $options = 0) {}

    /**
     * Creates a new DatePeriod object
     * @param string $isostr String containing the ISO interval.
     * @param int $options Can be set to DatePeriod::EXCLUDE_START_DATE.
     * @throws DateMalformedPeriodStringException
     */
    public function __construct($isostr, $options = 0) {}

    /**
     * Gets the interval
     * @return DateInterval Returns a DateInterval object
     * @since 5.6
     */
    public function getDateInterval(): DateInterval {}

    /**
     * Gets the end date
     * @return TEnd Returns null if the DatePeriod does not have an end date. For example, when initialized with the recurrences parameter, or the isostr parameter without an end date. Returns a DateTimeImmutable object when the DatePeriod is initialized with a DateTimeImmutable object as the end ...
     * @since 5.6
     */
    public function getEndDate(): ?DateTimeInterface {}

    /**
     * Gets the start date
     * @return TDate Returns a DateTimeImmutable object when the DatePeriod is initialized with a DateTimeImmutable object as the start parameter. Returns a DateTime object otherwise.
     * @since 5.6
     */
    public function getStartDate(): DateTimeInterface {}

    public static function __set_state(array $array): static {}

    public function __wakeup(): void {}

    /**
     * Get the number of recurrences
     * @return int|null The number of recurrences as set by explicitly passing the $recurrences to the constructor of the DatePeriod class, or null otherwise.
     * @since 7.2
     */
    public function getRecurrences(): ?int {}

    /**
     * @return \Iterator<int, TDate>
     * @since 8.0
     */
    public function getIterator(): Iterator {}

    public function __serialize(): array {}

    public function __unserialize(array $data): void {}

    /**
     * Creates a new DatePeriod object from an ISO8601 string
     *
     * Creates a new DatePeriod object from an ISO8601 string, as specified with specification.
     * @since 8.3
     * @throws \DateMalformedPeriodStringException Throws an DateMalformedPeriodStringException when the specification cannot be parsed as a valid ISO 8601 period.
     */
    public static function createFromISO8601String(string $specification, int $options = 0): static {}
}
