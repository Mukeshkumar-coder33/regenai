import * as React from 'react';
import { cn } from '@/lib/utils';
import { validateField, sanitizeInput } from '@/lib/validation';

const Input = React.forwardRef(function Input({
    className,
    type = 'text',
    value,
    defaultValue,
    onChange,
    onBlur,
    validationOptions,
    showValidationMessage = false,
    errorMessage,
    ...props
}, ref) {
    const generatedId = React.useId();
    const resolvedId = props.id || `input-${generatedId.replace(/[:]/g, '')}`;
    const resolvedName = props.name || resolvedId;
    const resolvedAutoComplete = props.autoComplete ?? (type === 'file' ? undefined : 'off');

    const [validationError, setValidationError] = React.useState(null);
    const [touched, setTouched] = React.useState(false);

    const handleBlur = (e) => {
        setTouched(true);
        const val = e.target.value;
        if (val) {
            const check = validateField(val, {
                type,
                label: props['aria-label'] || props.placeholder || 'Field',
                ...validationOptions,
            });
            setValidationError(check.valid ? null : check.error);
        } else {
            setValidationError(null);
        }
        if (onBlur) onBlur(e);
    };

    const handleChange = (e) => {
        // Sanitize dangerous script injection strings in real-time
        if (typeof e.target.value === 'string' && /<script|javascript:/i.test(e.target.value)) {
            e.target.value = sanitizeInput(e.target.value);
        }

        if (touched) {
            const val = e.target.value;
            if (val) {
                const check = validateField(val, {
                    type,
                    label: props['aria-label'] || props.placeholder || 'Field',
                    ...validationOptions,
                });
                setValidationError(check.valid ? null : check.error);
            } else {
                setValidationError(null);
            }
        }
        if (onChange) onChange(e);
    };

    const hasError = Boolean(errorMessage || (touched && validationError));
    const activeError = errorMessage || validationError;
    const isFlex1 = className && (className.includes('flex-1') || className.includes('flex-grow'));
    const isHidden = className && (className.includes('hidden') || type === 'file' && className.includes('hidden'));

    return (
        <div className={cn("relative w-full", isFlex1 && "flex-1 min-w-0", isHidden && "hidden", props.containerClassName)}>
            <input
                ref={ref}
                type={type}
                id={resolvedId}
                name={resolvedName}
                autoComplete={resolvedAutoComplete}
                value={value}
                defaultValue={defaultValue}
                onChange={handleChange}
                onBlur={handleBlur}
                aria-invalid={hasError || props['aria-invalid']}
                title={hasError ? activeError : props.title}
                data-slot="input"
                className={cn(
                    'file:text-foreground placeholder:text-[#829089] selection:bg-[#087A4B] selection:text-white border-[#E1E8E4] flex h-9.5 sm:h-10 lg:h-10.5 w-full min-w-0 rounded-lg sm:rounded-xl border bg-[#F8FAF9] px-3 sm:px-3.5 lg:px-4 py-1.5 sm:py-2 text-xs sm:text-sm text-[#17231F] shadow-2xs transition-all outline-none file:inline-flex file:h-7 file:border-0 file:bg-transparent file:text-xs file:font-semibold disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-50',
                    'focus-visible:border-[#087A4B] focus-visible:bg-white focus-visible:ring-2 focus-visible:ring-[#087A4B]/20',
                    hasError && 'border-[#DC4C4C] focus-visible:border-[#DC4C4C] focus-visible:ring-[#DC4C4C]/20 text-[#DC4C4C]',
                    className
                )}
                {...props}
            />
            {showValidationMessage && hasError && (
                <p className="text-[11px] font-medium text-rose-500 mt-1 pl-1 animate-in fade-in-50 duration-200">
                    {activeError}
                </p>
            )}
        </div>
    );
});

Input.displayName = 'Input';

export { Input };
