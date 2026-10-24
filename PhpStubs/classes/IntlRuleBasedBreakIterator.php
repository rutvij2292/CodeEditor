<?php

/**
 * A subclass of IntlBreakIterator that encapsulates ICU break iterators whose behavior is specified
 * using a set of rules. This is the most common kind of break iterators.
 *
 * These rules are described in the ICU Boundary Analysis User Guide.
 */
class IntlRuleBasedBreakIterator extends IntlBreakIterator implements Traversable
{
    /**
     * @param string $rules
     * @param bool $compiled [optional]
     */
    public function __construct(
        $rules,
        $compiled = false
    ) {}

    /**
     * @return string|false
     */
    public function getBinaryRules(): string|false {}

    /**
     * @return string|false
     */
    public function getRules(): string|false {}

    /**
     * @return int
     */
    public function getRuleStatus(): int {}

    /**
     * @return array|false
     */
    public function getRuleStatusVec(): array|false {}
}
