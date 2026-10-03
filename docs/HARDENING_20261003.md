# GardeFlow hardening — 2026-10-03

This change set hardens the canonical `source/` application and its Supabase rules.

Key invariants:
- same hospital is mandatory for shift requests;
- any exchange involving a Service guard requires the same service;
- the first-year promotion restriction applies only when Urgences are involved;
- disciplinary guards remain immutable to doctors;
- planning state is `draft/rejected -> submitted -> approved`;
- submitted/approved months are immutable;
- admin rejection/reopening blocks J+7 auto-validation until resubmission;
- an official PDF with zero assignments for one doctor is a valid sync result;
- Practice statistics use an immutable private response-event ledger;
- legacy top-level `lib/` is not the canonical Flutter source.
