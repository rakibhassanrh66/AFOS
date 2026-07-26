-- Club short names (abbreviations shown alongside the full proper name).
--
-- The full name in `clubs.name` stays authoritative and unchanged; this adds
-- the short form the UI leads with, e.g. "DIU Debating Club" -> DC and
-- "DIU Computer and Programming Club" -> CPC.
--
-- Deliberately a hand-written mapping rather than a generated one. Taking
-- initials mechanically collides badly on this data: Chess Club of DIU, DIU
-- Communication Club and DIU Cultural Club all reduce to "CC", and Daffodil
-- Running Community, DIU Readers' Club and DIU Robotics Club all reduce to
-- "RC". Existing acronyms (BNCC, AIRIS, CIS, EEE, HR, ITM, NFE, YES) are also
-- kept whole rather than re-initialled into nonsense. The institution prefix
-- ("DIU", "Daffodil", "of DIU", "- DIU") is dropped, per the short forms the
-- clubs actually use.

ALTER TABLE clubs ADD COLUMN IF NOT EXISTS short_name text;

UPDATE clubs c SET short_name = m.short_name
FROM (VALUES
  ('All Stars Daffodil',                                        'ASD'),
  ('Chess Club of DIU',                                         'CHC'),
  ('Daffodil AI Club',                                          'AIC'),
  ('Daffodil Entrepreneurs'' Club',                             'DEC'),
  ('Daffodil International University Research Society',        'RS'),
  ('Daffodil Moot Court Society',                               'MCS'),
  ('Daffodil Prothom Alo Bondhushava',                          'DPAB'),
  ('Daffodil Running Community',                                'DRC'),
  ('Data Science Club',                                         'DSC'),
  ('DIU Agricultural Science Club',                             'ASC'),
  ('DIU Air Rover Scout',                                       'ARS'),
  ('DIU AIRIS',                                                 'AIRIS'),
  ('DIU Band Society',                                          'BS'),
  ('DIU Blood Donors Club',                                     'BDC'),
  ('DIU BNCC',                                                  'BNCC'),
  ('DIU Business and Education Club',                           'BEC'),
  ('DIU Change Together Club',                                  'CTC'),
  ('DIU CIS Club',                                              'CISC'),
  ('DIU Civil Engineering Club',                                'CEC'),
  ('DIU Communication Club',                                    'CMC'),
  ('DIU Computer and Programming Club',                         'CPC'),
  ('DIU Creative Park',                                         'CP'),
  ('DIU Cultural Club',                                         'CLC'),
  ('DIU Cyber Security Club',                                   'CSC'),
  ('DIU Debating Club',                                         'DC'),
  ('DIU e-Business Club',                                       'EBC'),
  ('DIU EEE Club',                                              'EEEC'),
  ('DIU English Literary Club',                                 'ELC'),
  ('DIU Film Society',                                          'FS'),
  ('DIU Finance Club',                                          'FC'),
  ('DIU Girls'' Computer Programming Club',                     'GCPC'),
  ('DIU HR Club',                                               'HRC'),
  ('DIU Information & Communication Engineering Club',          'ICEC'),
  ('DIU Investment Club',                                       'IC'),
  ('DIU ITM Club',                                              'ITMC'),
  ('DIU Karate-Do Club',                                        'KDC'),
  ('DIU Marketing Club',                                        'MC'),
  ('DIU Model United Nations Association',                      'MUNA'),
  ('DIU NFE Club',                                              'NFEC'),
  ('DIU Photographic Society',                                  'PS'),
  ('DIU Public Health Club',                                    'PHC'),
  ('DIU Readers'' Club',                                        'RDC'),
  ('DIU Robotics Club',                                         'RBC'),
  ('DIU Software Engineering Club',                             'SEC'),
  ('DIU Study Abroad Forum',                                    'SAF'),
  ('DIU Textile Club',                                          'TC'),
  ('DIU Voluntary Service Club',                                'VSC'),
  ('DIU Youth Engagement and Support (YES) Club',               'YES'),
  ('Mathematical Society',                                      'MS'),
  ('Pharmacia Club - DIU',                                      'PC'),
  ('Real Estate Club - DIU',                                    'REC'),
  ('Rotaract Club of DIU',                                      'RTC'),
  ('SkillUp Club (HRDI)',                                       'SUC'),
  ('Social Business Students'' Forum',                          'SBSF'),
  ('Society for Young Business Leaders',                        'SYBL')
) AS m(name, short_name)
WHERE c.name = m.name;

-- Case-insensitive uniqueness so a future club cannot silently reuse an
-- abbreviation. NULL is still allowed (a club created before an abbreviation
-- is chosen), and NULLs do not collide with each other in a unique index.
CREATE UNIQUE INDEX IF NOT EXISTS clubs_short_name_unique_ci
  ON clubs (upper(short_name)) WHERE short_name IS NOT NULL;

-- Shape only: 1-8 chars, letters/digits/hyphen. Deliberately loose enough for
-- AIRIS and BNCC, tight enough that a full club name can't be pasted in here.
ALTER TABLE clubs DROP CONSTRAINT IF EXISTS clubs_short_name_format;
ALTER TABLE clubs ADD CONSTRAINT clubs_short_name_format
  CHECK (short_name IS NULL OR short_name ~ '^[A-Za-z0-9-]{1,8}$');
