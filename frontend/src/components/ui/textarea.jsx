import * as React from 'react';
import { cn } from '@/lib/utils';
import { sanitizeInput } from '@/lib/validation';

const Textarea = React.forwardRef(function Textarea({ className, onChange, maxLength = 5000, ...props }, ref) {
    const handleChange = (e) => {
        if (typeof e.target.value === 'string' && /<script|javascript:/i.test(e.target.value)) {
            e.target.value = sanitizeInput(e.target.value);
        }
        if (onChange) onChange(e);
    };

    return (
        <textarea
            ref={ref}
            data-slot="textarea"
            maxLength={maxLength}
            onChange={handleChange}
            className={cn(
                'border-[#E1E8E4] bg-[#F8FAF9] text-[#17231F] placeholder:text-[#829089] focus-visible:border-[#087A4B] focus-visible:bg-white focus-visible:ring-2 focus-visible:ring-[#087A4B]/20 aria-invalid:ring-[#DC4C4C]/20 aria-invalid:border-[#DC4C4C] flex field-sizing-content min-h-16 w-full rounded-xl border px-3.5 py-2.5 text-base shadow-xs transition-[color,box-shadow,border-color] outline-none disabled:cursor-not-allowed disabled:opacity-50 md:text-sm',
                className
            )}
            {...props}
        />
    );
});

Textarea.displayName = 'Textarea';

export { Textarea };
