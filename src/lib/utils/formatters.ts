export function formatDate(dateString: string): string {
	const date = new Date(dateString);
	return date.toLocaleDateString('en-AU', {
		day: '2-digit',
		month: 'short',
		year: 'numeric'
	});
}

export function formatTime(dateString: string): string {
	const date = new Date(dateString);
	return date.toLocaleTimeString('en-AU', {
		hour: '2-digit',
		minute: '2-digit',
		hour12: true
	});
}

export function formatCurrency(amount: number): string {
	return new Intl.NumberFormat('en-AU', {
		style: 'currency',
		currency: 'AUD'
	}).format(amount);
}

// Additional useful formatters
export function formatPhoneNumber(phone: string): string {
	return phone.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2 $3');
}

export function formatABN(abn: string): string {
	return abn.replace(/(\d{2})(\d{3})(\d{3})(\d{3})/, '$1 $2 $3 $4');
}

export function formatMobileNumber(number: string): string {
	// Remove all non-digit characters
	const cleaned = number.replace(/\D/g, '');

	// Handle numbers with or without country code
	if (cleaned.startsWith('61')) {
		return `+61 ${cleaned.slice(2, 5)} ${cleaned.slice(5, 8)} ${cleaned.slice(8)}`;
	}

	if (cleaned.startsWith('0')) {
		return `${cleaned.slice(0, 4)} ${cleaned.slice(4, 7)} ${cleaned.slice(7)}`;
	}

	// Default formatting for 10-digit numbers
	return `${cleaned.slice(0, 4)} ${cleaned.slice(4, 7)} ${cleaned.slice(7)}`;
}

// Usage examples:
// formatMobileNumber('0412345678') -> '0412 345 678'
// formatMobileNumber('61412345678') -> '+61 412 345 678'
// formatMobileNumber('+61412345678') -> '+61 412 345 678'
