import { cn } from '@/lib/utils'

// جدول بهوية الموقع: رأس ملطف بحدود سفلية، صفوف بتباعد مريح وhover،
// وأرقام tabular-nums ثابتة العرض.

export function Table({ children, className, ...props }: React.HTMLAttributes<HTMLTableElement>) {
  return (
    <table {...props} className={cn('w-full caption-bottom border-collapse text-sm', className)}>
      {children}
    </table>
  )
}

export function TableHeader({ children, className, ...props }: React.HTMLAttributes<HTMLTableSectionElement>) {
  return (
    <thead {...props} className={cn('[&_tr]:border-b [&_tr]:hover:bg-transparent', className)}>
      {children}
    </thead>
  )
}

export function TableBody({ children, className, ...props }: React.HTMLAttributes<HTMLTableSectionElement>) {
  return (
    <tbody {...props} className={cn('[&_tr:last-child]:border-0', className)}>
      {children}
    </tbody>
  )
}

export function TableRow({ children, className, ...props }: React.HTMLAttributes<HTMLTableRowElement>) {
  return (
    <tr
      {...props}
      className={cn(
        'border-b border-border/70 transition-colors hover:bg-muted/40 data-[state=selected]:bg-muted',
        className,
      )}
    >
      {children}
    </tr>
  )
}

export function TableHead({ children, className, ...props }: React.HTMLAttributes<HTMLTableCellElement>) {
  return (
    <th
      {...props}
      className={cn(
        'h-10 whitespace-nowrap bg-muted/40 px-3 text-start align-middle text-xs font-semibold text-muted-foreground',
        className,
      )}
    >
      {children}
    </th>
  )
}

export function TableCell({ children, className, ...props }: React.HTMLAttributes<HTMLTableCellElement>) {
  return (
    <td {...props} className={cn('px-3 py-2.5 align-middle', className)}>
      {children}
    </td>
  )
}
