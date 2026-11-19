import { Link } from 'react-router-dom';
import { PublicShell } from '../components/PublicShell';

export function NotFound() {
  return (
    <PublicShell title="Page not found">
      <p className="mb-4 text-sm">That page does not exist.</p>
      <Link to="/" className="underline">
        Go to the home page
      </Link>
    </PublicShell>
  );
}
