import csv
import re
import os

sql_file = '/Users/suriyaprakash/Downloads/grocery_products_1000plus_seed (1).sql'
csv_file = '/Users/suriyaprakash/Downloads/grocery_products_import.csv'

# INSERT INTO products (name_en, name_ta, name_thanglish, category, unit, price, tax_percent, stock_qty, barcode) VALUES
# ('Sona Masoori Rice 500g', 'சோனா மசூரி அரிசி 500 கிராம்', 'Sona Masoori Arisi 500g', 'Rice & Grains', '500g', 31, 0, 40, '8900000000001'),

if not os.path.exists(sql_file):
    print("SQL file not found!")
    exit(1)

with open(sql_file, 'r', encoding='utf-8') as f:
    content = f.read()

# find all tuples: ('...', '...', '...', ...)
pattern = re.compile(r"\((.*?)\)", re.DOTALL)
matches = pattern.findall(content)

with open(csv_file, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    # Header
    writer.writerow(['name', 'searchAliases', 'barcode', 'unit', 'price', 'costPrice', 'stockQty'])
    
    count = 0
    for match in matches:
        if 'name_en' in match: 
            continue # Skip header tuple if any
        
        # Split by comma but respect single quotes
        # A simple hack for this specific sql dump: split by ", "
        # It's better to use csv reader with quotechar="'"
        try:
            row = [x.strip().strip("'") for x in list(csv.reader([match], quotechar="'", skipinitialspace=True))[0]]
            if len(row) >= 9:
                name_en = row[0]
                name_ta = row[1]
                name_thanglish = row[2]
                unit = row[4]
                price = row[5]
                stock_qty = row[7]
                barcode = row[8]
                
                name = f"{name_en} - {name_ta}"
                aliases = f"{name_thanglish}"
                cost_price = "0"
                
                writer.writerow([name, aliases, barcode, unit, price, cost_price, stock_qty])
                count += 1
        except Exception as e:
            pass

print(f"Converted {count} products to {csv_file}")
