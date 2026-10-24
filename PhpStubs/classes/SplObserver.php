<?php

/**
 * The SplObserver interface is used alongside
 * SplSubject to implement the Observer Design Pattern.
 */
interface SplObserver
{
    /**
     * Receive update from subject
     * @param SplSubject $subject The SplSubject notifying the observer of an update.
     * @return void
     */
    public function update(SplSubject $subject): void;
}
