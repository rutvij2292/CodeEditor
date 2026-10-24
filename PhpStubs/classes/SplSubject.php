<?php

/**
 * The SplSubject interface is used alongside
 * SplObserver to implement the Observer Design Pattern.
 */
interface SplSubject
{
    /**
     * Attach an SplObserver
     * @param SplObserver $observer The SplObserver to attach.
     * @return void
     */
    public function attach(SplObserver $observer): void;

    /**
     * Detach an observer
     * @param SplObserver $observer The SplObserver to detach.
     * @return void
     */
    public function detach(SplObserver $observer): void;

    /**
     * Notify an observer
     * @return void
     */
    public function notify(): void;
}
