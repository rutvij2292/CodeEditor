<?php

/**
 * Normalization is a process that involves transforming characters and sequences of characters into
 * a formally-defined underlying representation. This process is most important when text needs to
 * be compared for sorting and searching, but it is also used when storing text to ensure that the
 * text is stored in a consistent representation.
 *
 * The Unicode Consortium has defined a number of normalization forms reflecting the various needs
 * of applications: Normalization Form D (NFD) - Canonical Decomposition Normalization Form C (NFC)
 * - Canonical Decomposition followed by Canonical Composition Normalization Form KD (NFKD) -
 * Compatibility Decomposition Normalization Form KC (NFKC) - Compatibility ...
 */
class Normalizer
{
    public const NFKC_CF = 48;

    public const FORM_KC_CF = 48;

    /**
     * Default normalization options
     */
    public const OPTION_DEFAULT = "";

    /**
     * No decomposition/composition
     * @removed 8.0
     */
    public const NONE = "1";

    /**
     * Normalization Form D (NFD) - Canonical Decomposition
     */
    public const FORM_D = 4;

    public const NFD = 4;

    /**
     * Normalization Form KD (NFKD) - Compatibility Decomposition
     */
    public const FORM_KD = 8;

    public const NFKD = 8;

    /**
     * Normalization Form C (NFC) - Canonical Decomposition followed by
     * Canonical Composition
     */
    public const FORM_C = 16;

    public const NFC = 16;

    /**
     * Normalization Form KC (NFKC) - Compatibility Decomposition, followed by
     * Canonical Composition
     */
    public const FORM_KC = 32;

    public const NFKC = 32;

    /**
     * Normalizes the input provided and returns the normalized string
     * @param string $string The input string to normalize
     * @param int $form One of the normalization forms.
     * @return string|false The normalized string or FALSE if an error occurred.
     */
    public static function normalize(
        $string,
        $form,
        $form = Normalizer::FORM_C,
        $arg3
    ): string|false {}

    /**
     * Checks if the provided string is already in the specified normalization form.
     * @param string $string The input string to normalize
     * @param int $form One of the normalization forms.
     * @return bool TRUE if normalized, FALSE otherwise or if there an error
     */
    public static function isNormalized(
        $string,
        $form,
        $form = Normalizer::FORM_C,
        $arg3
    ): bool {}

    /**
     * Gets the Decomposition_Mapping property for the given UTF-8 encoded code point
     *
     * Gets the Decomposition_Mapping property, as specified in the Unicode Character Database
     * (UCD), for the given UTF-8 encoded code point.
     * @param string $string The input string to normalize
     * @param int $form
     * @return string|null Returns a string containing the Decomposition_Mapping property, if present in the UCD. Returns null if there is no Decomposition_Mapping property for the character.
     * @since 7.3
     */
    public static function getRawDecomposition(
        string $string,
        int $form = 16
    ): ?string {}
}
