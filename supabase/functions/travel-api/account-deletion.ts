import { platform } from './platform.ts';
import { requireValue, uuid } from './validation.ts';

// Storage is not part of Auth's cascading database transaction. Remove objects
// first so a failed cleanup leaves an authenticated account that can retry.
// Include abandoned uploads and old versions, not only current document paths.
export async function deleteAccount(actor: string) {
  requireValue(uuid(actor), 'Invalid account.', 401);
  const folders = [actor.toLowerCase()];
  const keys: string[] = [];
  for (let i = 0; i < folders.length; i++) {
    const prefix = folders[i];
    for (let offset = 0;; offset += 100) {
      const rows = await platform('/storage/v1/object/list/journey-photos', 'POST', {
        prefix, limit: 100, offset, sortBy: { column: 'name', order: 'asc' },
      });
      requireValue(Array.isArray(rows), 'Could not list account photos. Please try again.', 502);
      for (const row of rows) {
        requireValue(typeof row.name === 'string' && row.name.length > 0 &&
          !row.name.includes('/') && !['.', '..'].includes(row.name),
          'Could not list account photos. Please try again.', 502);
        const path = prefix + '/' + row.name;
        if (row.id == null) folders.push(path);
        else keys.push(path);
      }
      if (rows.length < 100) break;
    }
  }
  // Finish enumeration before deleting: removing a page shifts later offsets.
  for (let i = 0; i < keys.length; i += 100) {
    await platform('/storage/v1/object/journey-photos', 'DELETE', {
      prefixes: keys.slice(i, i + 100),
    });
  }
  // Cascades revoke every opaque app session, flight watch, share and cloud row.
  // Never return success until Auth confirms deletion.
  await platform('/auth/v1/admin/users/' + actor, 'DELETE');
  return { ok: true };
}
