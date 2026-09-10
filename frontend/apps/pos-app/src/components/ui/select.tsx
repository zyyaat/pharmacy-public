'use client'

// قائمة منسدلة حقيقية من الموقع نفسه — بديل كامل لقائمة <select> الخاصة بالمتصفح.
//
// - متوافقة مع RTL ولوحة المفاتيح (أسهم / Home / End / Enter / Esc / Tab)
// - تفتح لأعلى تلقائياً عندما لا يوجد مساحة كافية بالأسفل
// - تدعم النماذج عبر hidden input عند تمرير name (تعمل مع FormData)
// - نفس هوية Input (حدود/ارتفاع/تركيز) مع مقاس sm لصفوف الفلاتر

import * as React from 'react'
import { Check, ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'

export interface SelectOption {
  value: string
  label: string
  disabled?: boolean
}

export interface SelectProps {
  options: SelectOption[]
  value?: string
  defaultValue?: string
  onValueChange?: (value: string) => void
  /** اسم الحقل داخل النماذج — يضيف hidden input بقيمة الخيار المختار */
  name?: string
  placeholder?: string
  size?: 'sm' | 'default'
  disabled?: boolean
  required?: boolean
  id?: string
  'aria-label'?: string
  className?: string
}

export const Select = React.forwardRef<HTMLButtonElement, SelectProps>(
  (
    {
      options,
      value: controlledValue,
      defaultValue,
      onValueChange,
      name,
      placeholder = 'اختر…',
      size = 'default',
      disabled,
      required,
      id,
      'aria-label': ariaLabel,
      className,
    },
    ref,
  ) => {
    const isControlled = controlledValue !== undefined
    const [internalValue, setInternalValue] = React.useState(defaultValue ?? '')
    const value = isControlled ? controlledValue : internalValue
    const [open, setOpen] = React.useState(false)
    const [activeIndex, setActiveIndex] = React.useState(-1)
    const [dropUp, setDropUp] = React.useState(false)
    const rootRef = React.useRef<HTMLDivElement>(null)
    const listRef = React.useRef<HTMLDivElement>(null)

    const selected = options.find((option) => option.value === value)
    const enabledIndexes = React.useMemo(
      () => options.map((option, index) => (option.disabled ? -1 : index)).filter((index) => index >= 0),
      [options],
    )

    const openListbox = React.useCallback(() => {
      if (disabled) return
      const rect = rootRef.current?.getBoundingClientRect()
      setDropUp(rect ? window.innerHeight - rect.bottom < 240 && rect.top > 280 : false)
      const currentIndex = options.findIndex((option) => option.value === value)
      setActiveIndex(currentIndex >= 0 ? currentIndex : enabledIndexes[0] ?? -1)
      setOpen(true)
    }, [disabled, options, value, enabledIndexes])

    const commit = React.useCallback(
      (optionValue: string) => {
        if (!isControlled) setInternalValue(optionValue)
        onValueChange?.(optionValue)
        setOpen(false)
        rootRef.current?.querySelector('button')?.focus()
      },
      [isControlled, onValueChange],
    )

    // إغلاق عند الضغط خارج القائمة أو تغيير الحجم
    React.useEffect(() => {
      if (!open) return
      function handlePointerDown(event: PointerEvent) {
        if (!rootRef.current?.contains(event.target as Node)) setOpen(false)
      }
      document.addEventListener('pointerdown', handlePointerDown)
      return () => document.removeEventListener('pointerdown', handlePointerDown)
    }, [open])

    // تمرير الخيار النشط لموضع مرئي
    React.useEffect(() => {
      if (!open || activeIndex < 0) return
      listRef.current
        ?.querySelector(`[data-index="${activeIndex}"]`)
        ?.scrollIntoView({ block: 'nearest' })
    }, [open, activeIndex])

    function handleKeyDown(event: React.KeyboardEvent) {
      if (disabled) return
      switch (event.key) {
        case 'Enter':
        case ' ':
          event.preventDefault()
          if (open) {
            if (activeIndex >= 0 && !options[activeIndex]?.disabled) commit(options[activeIndex].value)
          } else {
            openListbox()
          }
          break
        case 'ArrowDown':
          event.preventDefault()
          if (!open) {
            openListbox()
          } else {
            event.preventDefault()
            setActiveIndex((current) => {
              const next = enabledIndexes.filter((index) => index > current)[0]
              return next ?? current
            })
          }
          break
        case 'ArrowUp':
          if (!open) {
            event.preventDefault()
            openListbox()
          } else {
            event.preventDefault()
            setActiveIndex((current) => {
              const previous = [...enabledIndexes].reverse().filter((index) => index < current)[0]
              return previous ?? current
            })
          }
          break
        case 'Home':
          if (open) {
            event.preventDefault()
            setActiveIndex(enabledIndexes[0] ?? -1)
          }
          break
        case 'End':
          if (open) {
            event.preventDefault()
            setActiveIndex(enabledIndexes[enabledIndexes.length - 1] ?? -1)
          }
          break
        case 'Escape':
          if (open) {
            event.preventDefault()
            event.stopPropagation()
            setOpen(false)
          }
          break
        case 'Tab':
          setOpen(false)
          break
      }
    }

    return (
      <div ref={rootRef} className="relative w-full" onKeyDown={handleKeyDown}>
        {name && <input type="hidden" name={name} value={value} required={required} />}
        <button
          ref={ref}
          type="button"
          id={id}
          role="combobox"
          aria-controls={open ? `${id ?? 'select'}-listbox` : undefined}
          aria-expanded={open}
          aria-haspopup="listbox"
          aria-label={ariaLabel}
          disabled={disabled}
          onClick={() => (open ? setOpen(false) : openListbox())}
          className={cn(
            'flex h-10 w-full items-center justify-between gap-2 rounded-lg border border-input bg-background px-3 text-sm ring-offset-background transition-all duration-200',
            'hover:bg-accent/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2',
            'disabled:cursor-not-allowed disabled:opacity-50',
            size === 'sm' && 'h-9 rounded-md px-2.5 text-xs',
            !selected && 'text-muted-foreground',
            open && 'ring-2 ring-ring ring-offset-2',
            className,
          )}
        >
          <span className="truncate">{selected ? selected.label : placeholder}</span>
          <ChevronDown
            className={cn('h-4 w-4 shrink-0 text-muted-foreground transition-transform duration-200', open && 'rotate-180')}
          />
        </button>

        {open && (
          <div
            ref={listRef}
            id={`${id ?? 'select'}-listbox`}
            role="listbox"
            aria-activedescendant={activeIndex >= 0 ? `${id ?? 'select'}-option-${activeIndex}` : undefined}
            className={cn(
              'absolute z-50 max-h-60 w-full min-w-[10rem] overflow-auto rounded-lg border border-border bg-card py-1 shadow-lg',
              'animate-in fade-in-0 zoom-in-95',
              dropUp ? 'bottom-full mb-1' : 'top-full mt-1',
            )}
          >
            {options.length === 0 ? (
              <p className="px-3 py-2 text-sm text-muted-foreground">لا توجد خيارات</p>
            ) : (
              options.map((option, index) => {
                const isActive = index === activeIndex
                const isSelected = option.value === value
                return (
                  <div
                    key={option.value}
                    id={`${id ?? 'select'}-option-${index}`}
                    role="option"
                    aria-selected={isSelected}
                    aria-disabled={option.disabled || undefined}
                    data-index={index}
                    onMouseEnter={() => !option.disabled && setActiveIndex(index)}
                    onClick={() => {
                      if (!option.disabled) commit(option.value)
                    }}
                    className={cn(
                      'relative flex cursor-pointer select-none items-center gap-2 py-1.5 pe-3 ps-3 text-sm outline-none',
                      isActive && 'bg-accent text-accent-foreground',
                      option.disabled && 'pointer-events-none opacity-50',
                      isSelected && 'font-semibold',
                    )}
                  >
                    <span className="truncate">{option.label}</span>
                    {isSelected && <Check className="ms-auto h-4 w-4 shrink-0 text-primary" />}
                  </div>
                )
              })
            )}
          </div>
        )}
      </div>
    )
  },
)
Select.displayName = 'Select'
