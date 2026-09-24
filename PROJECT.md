# SeatChart — Project Handoff

## Product
**SeatChart**  
**Tagline:** School Examination & Seating Management

SeatChart is a multi-tenant school examination, exam-planning, roll-assignment, room-management and seating-management application.

## Technology / Architecture
- Frontend: HTML + CSS + Vanilla JavaScript
- Backend: Supabase
- Authentication: Supabase Auth using synthetic email + password internally
- Login UX: Indian 10-digit phone number + 6-digit PIN
- No OTP, SMS verification, Twilio, React or Node
- Deployment: Vercel
- Source of truth: GitHub
- Repository: https://github.com/gunjitsingh84/SeatChart
- Live app: https://seatchart-gmsss.vercel.app/
- Supabase project ref: iykvboyzviguuaejppkw
- Supabase region: ap-south-1
- Current main index.html SHA verified during handoff: 3fbc28743695d88211d3435a1539fb428745a0fa

## Development Rules
1. Inspect current main before changing code.
2. Preserve the existing codebase, functions, variables and API contracts unless the requested feature requires a change.
3. One feature/fix per branch and PR.
4. Full-file updates only when supplying code to the user; never use placeholders.
5. Verify JavaScript syntax before PR.
6. Test edge cases and perform 2–3 manual tests after each feature.
7. Do not commit unverified code.
8. Use short Git iterations.
9. Commit format: `feat: [Short explanation of what was added]` or `fix: [Short explanation of what was fixed]`.
10. Completed PRs should be merged into `main` after verification because the user tests on the live account.
11. Do not redesign working UI without an explicit request.
12. Never expose Supabase service/secret keys in browser code.
13. Keep school/tenant isolation on every school-owned query and mutation.

## Multi-Tenant Rules
- A user belongs to exactly one school.
- School-owned records are scoped by `school_id`.
- Academic data is also scoped to the current `session_id` where applicable.
- RLS is enabled on application tables.
- Never use another school's IDs or data.
- User creation is Administrator-only and is handled server-side by the Supabase Edge Function `create-school-user`.

## Current Navigation
1. Dashboard
2. Classes & Sections
3. Rooms
4. Subjects
5. Exam Planner
6. Exams
7. Settings
   - User Management
   - History
   - Profile Management

## Completed Modules

### Classes & Sections
- Class 1–12
- Sections A–J
- Student counts 1–99
- Add/edit/delete
- Excel import
- Session/class uniqueness
- Delete protections for subjects, roll assignments and seating dependencies
- DELETE ALL CLASSES & SECTIONS for current school/session with confirmation and dependency checks

### Rooms
- Room Number
- Room Name
- Bench Capacity
- Floor
- Status
- Physical layout: Rows + Columns
- Capacity is authoritative physical bench count
- Rows × Columns must be >= capacity
- Available rooms contribute to dashboard capacity
- Excel import
- Room-specific edit/delete
- DELETE ALL ROOMS
- Physical seating numbering is column-wise
- Current room deletion protection checks `sc_seating_assignments` before deleting a referenced room and shows a user-friendly message instead of a raw FK error

### Subjects
- Class-wise bulk add/edit
- Excel import
- Active/Inactive
- Assigned / Total roll counts
- Section-wise roll assignment
- Saved roll deselections are preserved
- Roll count pagination handles >1000 records
- New/imported subjects auto-initialize available roll assignments
- Subject deletion removes related roll assignments where allowed
- DELETE ALL SUBJECTS includes roll cleanup

### Dashboard
- Total students
- Classrooms
- Upcoming exams
- Seating status
- Academic/examination summary areas

### Authentication
- Phone + 6-digit PIN UX
- Synthetic email format:
  `digits@login.seatchart.app`
- Email confirmation disabled for this workflow
- School/profile bootstrap hardened against partial signup failures

### User Management
- Administrator can add Staff or Administrator users
- Full name, Indian phone, role, 6-digit PIN
- Protected Supabase Edge Function: `create-school-user`
- Auth user + school profile creation with rollback if profile creation fails

### Profile Management
- School name
- School address
- School phone
- School logo
- Logo is now uploaded as PNG/JPG/WEBP instead of entered as a URL
- Supabase Storage bucket: `school-logos`
- Max logo size: 2 MB
- School-scoped storage paths
- Replacing a logo cleans up the previous SeatChart-managed logo
- Administrator profile is displayed

### Exam Planner
- Create examination
- Constant paper timing for the plan
- Select classes
- Select subjects
- Randomized/distributed dates
- Study leave days between papers
- Sundays excluded
- 2nd Saturdays excluded
- Optional Saturdays
- Drag/drop calendar
- Conflict highlighting
- Validation
- Publish
- Published date-sheet print/export

### Exams
- Exam listing
- Exam details
- Date/class/subject schedule grid
- Generate seating plan from a specific exam date
- Published seating plan can be printed

## Seating Architecture
Flow:
**Exam Date → Scheduled Classes/Subjects → Subject Roll Assignments → Candidates → Seating Rules → Room Selection → Seating Generation → Validation → Publish → Room-wise Chart/Print**

### Seating rules
- 1 or 2 students per bench
- Same-class pair never allowed
- Same-subject classes cannot be paired
- Consecutive classes cannot be paired by default
- Allowed class pairings are selectable
- Both classes must have an exam on that exact date
- Explicit rule overrides are supported where the UI permits them

### Physical room rules
- Room layout uses configured rows and columns
- Capacity is the actual bench count
- Bench positions are numbered **column-wise**
- Example 10 rows × 4 columns:
  - Column 1: benches 1–10
  - Column 2: benches 11–20
  - Column 3: benches 21–30
  - Column 4: benches 31–40
- Each room's bench numbering starts at 1
- Selected rooms are filled **sequentially to capacity**: completely fill Room 1 before Room 2, then Room 3, etc.
- Only the last used room should have unused physical positions

### Seating output
- Physical table/grid view
- Cells show roll + Class-Section, not subject
- Room Candidate List consolidates Class/Section + Subject + roll ranges
- Example class labels use Roman numerals I–XII, e.g. X-B
- Room-wise print/export uses the published plan

### Seating persistence
Tables:
- `sc_seating_plans`
- `sc_seating_assignments`

Published plan uniqueness is per exam/date.

## Recent Seating Fixes
- Column-wise physical bench numbering implemented
- Sequential room filling corrected so each selected room is consumed to physical bench capacity before moving to the next
- Room ordering is numeric-aware
- Physical chart uses the same column-wise position model
- Current main includes these fixes

## Backlog Features — Implemented
These were previously parked and are now implemented on main:
1. **Auto Refresh**
   - Refreshes the active SeatChart module every 1 minute
   - Starts after authenticated bootstrap
   - Avoids refresh while a modal is open
2. **Auto Logout**
   - 30-minute inactivity timeout
   - Activity resets the timer
   - Background timer is cleared during logout
3. **CTA Loading State**
   - Primary CTA processing state
   - Prevents repeated submissions
   - Spinner/disabled state with safety restoration

## Current Known Operational Notes
- Existing published seating plans are not automatically regenerated after a seating-generation logic change; generate a new plan when testing allocation changes.
- Room deletion is intentionally blocked when the room is referenced by seating assignments, preserving historical seating data.
- If a room is referenced by an existing seating plan, use the user-facing dependency message rather than attempting a direct database delete.
- The room layout/capacity model must remain consistent: rows × columns >= capacity.
- Existing database tables and historical seating records should not be destructively altered without explicit requirement.

## Supabase Schema
Core tables:
- `sc_schools`
- `sc_academic_sessions`
- `sc_user_profiles`
- `sc_classes`
- `sc_sections`
- `sc_rooms`
- `sc_subjects`
- `sc_subject_rolls`
- `sc_history`
- `sc_exams`
- `sc_exam_schedules`
- `sc_exam_breaks`
- `sc_seating_plans`
- `sc_seating_assignments`

## Supabase Storage
Bucket:
- `school-logos`
- Public read
- Authenticated Administrator upload/update/delete restricted to the user's school folder
- Accepted: PNG/JPEG/WEBP
- Maximum: 2 MB

## Important Current Git State
- Main branch is the production development baseline.
- Always branch from current `main`.
- Merge completed PRs into `main` after verification.
- Current main was successfully fetched during this handoff, confirming GitHub connectivity and repository access.
- A project handoff document is being added as `PROJECT.md` so future chats can use the repository itself as the durable project context.

## Next-Chat Startup Procedure
When starting a new SeatChart development chat:
1. Read this `PROJECT.md`.
2. Fetch the current `main` `index.html`.
3. Check the latest merged PR/commit before making changes.
4. Inspect the relevant current function before editing it.
5. Make exactly one requested feature/fix.
6. Verify JavaScript syntax.
7. Create a feature/fix branch.
8. Open PR.
9. Merge the verified PR into `main`.
10. Tell the user the merge commit and what to test live.

Do not rebuild or redesign SeatChart from scratch. Continue from the current repository state.
