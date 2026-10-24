<?php

/**
 * Classes implementing RecursiveIterator can be used to iterate
 * over iterators recursively.
 */
interface RecursiveIterator extends Iterator
{
    /**
     * Returns if an iterator can be created for the current entry.
     * @return bool true if the current entry can be iterated over, otherwise returns false.
     */
    public function hasChildren(): bool;

    /**
     * Returns an iterator for the current entry.
     * @return RecursiveIterator|null An iterator for the current entry.
     */
    public function getChildren(): ?RecursiveIterator;
}
