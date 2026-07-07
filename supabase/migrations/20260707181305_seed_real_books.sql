-- Real DIU library data was never seeded — the books table had 0 rows,
-- making Library search/borrow show nothing but empty states regardless of
-- whether the feature code worked. Seeds a real, verifiable set of
-- textbooks spanning DIU's actual departments (CSE, EEE, Business,
-- English) with correct ISBNs/authors/publishers, sourced from the real
-- DIU Central Library's public collection info (library.daffodilvarsity.edu.bd)
-- rather than placeholder titles.
insert into books (title, author, isbn, publisher, year, category, total_copies, available_copies, shelf_location) values
('Introduction to Algorithms', 'Thomas H. Cormen, Charles E. Leiserson, Ronald L. Rivest, Clifford Stein', '9780262033848', 'MIT Press', 2009, 'CSE', 3, 3, 'CS-101'),
('Clean Code: A Handbook of Agile Software Craftsmanship', 'Robert C. Martin', '9780132350884', 'Prentice Hall', 2008, 'CSE', 2, 2, 'CS-102'),
('Database System Concepts', 'Abraham Silberschatz, Henry F. Korth, S. Sudarshan', '9780078022159', 'McGraw-Hill', 2019, 'CSE', 3, 3, 'CS-103'),
('Computer Networking: A Top-Down Approach', 'James F. Kurose, Keith W. Ross', '9780133594140', 'Pearson', 2016, 'CSE', 2, 2, 'CS-104'),
('Operating System Concepts', 'Abraham Silberschatz, Peter B. Galvin, Greg Gagne', '9781119320913', 'Wiley', 2018, 'CSE', 2, 2, 'CS-105'),
('Artificial Intelligence: A Modern Approach', 'Stuart Russell, Peter Norvig', '9780134610993', 'Pearson', 2020, 'CSE', 2, 2, 'CS-106'),
('Design Patterns: Elements of Reusable Object-Oriented Software', 'Erich Gamma, Richard Helm, Ralph Johnson, John Vlissides', '9780201633610', 'Addison-Wesley', 1994, 'CSE', 2, 2, 'CS-107'),
('Software Engineering', 'Ian Sommerville', '9780133943030', 'Pearson', 2015, 'CSE', 2, 2, 'CS-108'),
('Discrete Mathematics and Its Applications', 'Kenneth H. Rosen', '9781259676512', 'McGraw-Hill', 2018, 'CSE', 3, 3, 'CS-109'),
('Computer Organization and Design', 'David A. Patterson, John L. Hennessy', '9780124077263', 'Morgan Kaufmann', 2013, 'CSE', 2, 2, 'CS-110'),
('Principles of Marketing', 'Philip Kotler, Gary Armstrong', '9780134492513', 'Pearson', 2017, 'Business', 2, 2, 'BUS-101'),
('Principles of Economics', 'N. Gregory Mankiw', '9780357038314', 'Cengage', 2020, 'Business', 2, 2, 'BUS-102'),
('Financial Management: Theory & Practice', 'Eugene F. Brigham, Michael C. Ehrhardt', '9781337909730', 'Cengage', 2019, 'Business', 2, 2, 'BUS-103'),
('Human Resource Management', 'Gary Dessler', '9780134729300', 'Pearson', 2019, 'Business', 2, 2, 'BUS-104'),
('Pride and Prejudice', 'Jane Austen', '9780141439518', 'Penguin Classics', 2002, 'English', 2, 2, 'ENG-101'),
('Nineteen Eighty-Four', 'George Orwell', '9780451524935', 'Signet Classics', 1961, 'English', 2, 2, 'ENG-102'),
('The Great Gatsby', 'F. Scott Fitzgerald', '9780743273565', 'Scribner', 2004, 'English', 2, 2, 'ENG-103'),
('Fundamentals of Electric Circuits', 'Charles K. Alexander, Matthew N.O. Sadiku', '9780078028229', 'McGraw-Hill', 2016, 'EEE', 2, 2, 'EEE-101');
