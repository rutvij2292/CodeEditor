<?php

/**
 * Weak references allow the programmer to retain a reference to an
 * object which does not prevent the object from being destroyed.
 * They are useful for implementing cache like structures.
 * @template T of object
 * @since 7.4
 */
final class WeakReference
{
    /**
     * This method exists only to disallow instantiation of the WeakReference
     * class. Weak references are to be instantiated with the factory method
     * WeakReference::create().
     */
    public function __construct() {}

    /**
     * Create a new weak reference.
     * @template TIn of object
     * @param TIn $object Any object.
     * @return WeakReference<TIn> The freshly instantiated object.
     * @since 7.4
     */
    public static function create(object $object): WeakReference {}

    /**
     * Gets a weakly referenced object. If the object has already been
     * destroyed, NULL is returned.
     * @return T|null Returns the referenced object, or null if the object has been destroyed.
     * @since 7.4
     */
    public function get(): ?object {}
}
