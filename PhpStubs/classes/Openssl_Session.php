<?php
namespace Openssl;

/**
 * @since 8.6
 */
final class Session
{
    public readonly string $id;

    public function export(int $format = 2): string {}

    public static function import(string $data, int $format = 2): Session {}

    public function isResumable(): bool {}

    public function getTimeout(): int {}

    public function getCreatedAt(): int {}

    public function getProtocol(): ?string {}

    public function getCipher(): ?string {}

    public function hasTicket(): bool {}

    public function getTicketLifetimeHint(): ?int {}

    public function __serialize(): array {}

    public function __unserialize(array $data): void {}
}
