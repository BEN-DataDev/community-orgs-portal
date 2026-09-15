import type { User } from '@supabase/supabase-js';

export interface Membership {
	organisation_id: string;
	organisation_name: string;
	max_hierarchy_level: number;
	role_names: string[];
}

export function displayName(user: User | null): string {
	for (const value of [
		user?.user_metadata?.display_name,
		user?.user_metadata?.full_name,
		user?.user_metadata?.name
	]) {
		if (typeof value === 'string' && value.trim()) return value.trim();
	}
	return user?.email?.split('@')[0] || 'Account';
}

export function accessLabel(memberships: Membership[] | null): string {
	if (memberships === null) return 'Access unavailable';
	const level = Math.max(0, ...memberships.map((org) => org.max_hierarchy_level));
	if (level >= 4) return 'Organisation owner';
	if (level >= 3) return 'Organisation admin';
	if (level >= 2) return 'Organisation moderator';
	if (level >= 1) return 'Organisation member';
	return 'No organisation roles';
}
