export type Role = 'student' | 'mentor' | 'supervisor' | 'admin';

export type EnrollmentStatus =
  | 'awaiting_approval' | 'active' | 'payment_due' | 'lapsed'
  | 'refund_requested' | 'left' | 'rejected';

export interface Profile {
  id: string;
  role: Role;
  full_name: string;
  email: string;
  phone: string | null;
  is_active: boolean;
}

export interface SettingRow {
  key: string;
  value: unknown;
  description: string;
  updated_at: string;
}
