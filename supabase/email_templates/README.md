# Room Rig auth email templates

Dark cyan UI matching the Flutter app (`AppColors`). Email clients strip most CSS frameworks — these use **inline styles + tables**, not Tailwind.

## Paste into Supabase

Dashboard → [Authentication → Email Templates](https://supabase.com/dashboard/project/iovnmgwthmevvvtszhrq/auth/templates)

| File | Dashboard template | Suggested subject |
|------|--------------------|-------------------|
| `confirm_email.html` | **Confirm signup** | `Confirm your Room Rig email` |
| `reset_password.html` | **Reset password** | `Reset your Room Rig password` |
| `change_password.html` | **Password changed** (security notification) | `Your Room Rig password was changed` |

For **Password changed**, enable the security notification toggle on that template (or Auth → notifications) so it actually sends.

Do **not** enable Brevo “email tracking” — it rewrites links and breaks Supabase confirm URLs.
