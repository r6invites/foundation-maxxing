import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { APP_NAME } from '../config';

interface PublicSettings {
  program_name?: string;
}

/** Program name from the database (public whitelist, so it works signed out too). */
export function useProgramName(): string {
  const { data } = useQuery({
    queryKey: ['public-settings'],
    queryFn: async () => {
      const { data: settings, error } = await supabase.rpc('public_settings');
      if (error) throw error;
      return settings as PublicSettings;
    },
    staleTime: 5 * 60 * 1000,
  });
  const name = data?.program_name?.trim();
  return name ? name : APP_NAME;
}

/** Keeps the browser tab title in step with the program name. */
export function useDocumentTitle(): void {
  const name = useProgramName();
  useEffect(() => {
    document.title = name;
  }, [name]);
}
