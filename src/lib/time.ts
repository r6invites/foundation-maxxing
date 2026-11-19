import { format } from 'date-fns';
import { tz } from '@date-fns/tz';

/** Every date and time in the app is shown in Indian Standard Time. */
export const IST = 'Asia/Kolkata';

export function formatIST(value: Date | string, pattern = 'dd MMM yyyy, h:mm a'): string {
  const date = typeof value === 'string' ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) return '';
  return format(date, pattern, { in: tz(IST) });
}
