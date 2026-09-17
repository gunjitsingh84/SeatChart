# SeatChart

**School Examination & Seating Management**

SeatChart is a mobile-first school examination management application for academic setup and, in later releases, examination planning and seating management.

## Current scope

The current codebase focuses on the **Academics** module:

- Classes & Sections
- Section student counts
- Rooms
- Subjects by class
- Subject-specific roll-number assignment
- Excel import for Classes & Sections
- Excel import for Rooms
- Academic session handling (April–March)
- Tenant-scoped history
- Supabase authentication and row-level tenant isolation

The Examination section remains intentionally deferred while the Academics foundation is being finalized.

## Technology

- HTML
- CSS
- Vanilla JavaScript
- Supabase JS v2 CDN
- SheetJS CDN for Excel import
- Supabase PostgreSQL + Auth + RLS

No React or Node.js build step is required for the current frontend.

## Local development

Open `index.html` in a browser or serve the repository root with any static HTTP server.

The app is configured for the SeatChart Supabase project and uses the browser-safe public/anon key. **Never replace it with a service-role key.** Authorization and tenant isolation are enforced through Supabase RLS.

For the no-SMS phone + 6-digit PIN workflow, phone confirmation must be disabled in the Supabase Auth provider settings.

## Vercel deployment

This is a static frontend, so Vercel can deploy it directly from this repository:

1. Import `gunjitsingh84/SeatChart` into Vercel.
2. Select the project root as the root directory.
3. Leave the build command empty.
4. Use `.` as the output directory when Vercel asks for one.
5. Deploy.

No Node.js build or environment-variable injection is required by the current static frontend.

## Repository structure

```text
/
├── index.html
├── README.md
└── sample-files/
    ├── SeatChart-Classes-Sample.xlsx
    └── SeatChart-Rooms-Sample.xlsx
```

## Important security note

The frontend contains only the Supabase project URL and public/anon key intended for browser use. Do not commit Supabase service-role/secret keys, database passwords, or other privileged credentials.
