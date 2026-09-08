export function Table({ children, ...props }: React.HTMLAttributes<HTMLTableElement>) {
  return (
    <table {...props} className="w-full border-collapse">
      {children}
    </table>
  )
}

export function TableHeader({ children, ...props }: React.HTMLAttributes<HTMLTableSectionElement>) {
  return <thead {...props}>{children}</thead>
}

export function TableBody({ children, ...props }: React.HTMLAttributes<HTMLTableSectionElement>) {
  return <tbody {...props}>{children}</tbody>
}

export function TableRow({ children, ...props }: React.HTMLAttributes<HTMLTableRowElement>) {
  return <tr {...props}>{children}</tr>
}

export function TableHead({ children, ...props }: React.HTMLAttributes<HTMLTableCellElement>) {
  return <th {...props}>{children}</th>
}

export function TableCell({ children, ...props }: React.HTMLAttributes<HTMLTableCellElement>) {
  return <td {...props}>{children}</td>
}
