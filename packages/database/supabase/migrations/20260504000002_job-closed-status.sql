-- Add "Closed" to the jobStatus enum
ALTER TYPE "jobStatus" ADD VALUE IF NOT EXISTS 'Closed';
