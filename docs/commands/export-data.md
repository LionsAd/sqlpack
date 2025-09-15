# Export Data (BCP)

Exports table data using `bcp` in native format with `.fmt` files. Useful for advanced or selective data moves.

## Examples

```bash
# Export data for listed tables to ./data
sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt
```

`./tables.txt` should contain `Schema.Table` names, one per line.

