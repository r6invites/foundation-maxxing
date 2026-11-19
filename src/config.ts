/**
 * Fallback program name, used until the real name loads from the database (settings key
 * `program_name`) and in the page title before any data arrives. To rename the product,
 * change the setting in the database; change this constant only to alter the fallback.
 */
export const APP_NAME = 'Foundation Maxxing';

/** Minimum password length. Keep in step with minimum_password_length in supabase/config.toml. */
export const MIN_PASSWORD_LENGTH = 10;
