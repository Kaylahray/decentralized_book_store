#[derive(Drop, Clone, Serde, starknet::Store)]
struct Book {
    title: felt252,
    description: felt252,
    price: u128,
    author: felt252,
    quantity: u32,
}
use core::starknet::ContractAddress;

// Interfaces
#[starknet::interface]
trait IBookstore<TContractState> {
    fn add_book(ref self: TContractState, book: Book);
    fn update_book(ref self: TContractState, book_id: u64, price: u128, quantity: u32);
    fn remove_book(ref self: TContractState, book_id: u64);
    fn get_book(self: @TContractState, book_id: u64) -> Book;
    fn get_book_count(self: @TContractState) -> u64;
    fn purchase_book(ref self: TContractState, book_id: u64, quantity: u32);
}

// Bookstore contract
#[starknet::contract]
mod Bookstore {
    use super::Book;
    use core::starknet::{ContractAddress, get_caller_address};
    use core::starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry};

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BookAdded: BookAdded,
        BookUpdated: BookUpdated,
        BookRemoved: BookRemoved,
        BookSold: BookSold,
    }

    #[derive(Drop, starknet::Event)]
    struct BookAdded {
        book_id: u64,
        book: Book,
    }

    #[derive(Drop, starknet::Event)]
    struct BookUpdated {
        book_id: u64,
        price: u128,
        quantity: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct BookRemoved {
        book_id: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct BookSold {
        book_id: u64,
        quantity: u32,
        buyer: ContractAddress,
    }

    #[storage]
    struct Storage {
        books: Map<u64, Book>,
        owner: ContractAddress,
        book_count: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.owner.write(owner);
        self.book_count.write(0);
    }

    #[abi(embed_v0)]
    impl BookstoreImpl of super::IBookstore<ContractState> {
        fn add_book(ref self: ContractState, book: Book) {
            assert(self.owner.read() == get_caller_address(), 'Not owner');
            let book_id = self.book_count.read();
            self.books.entry(book_id).write(book.clone());
            self.book_count.write(book_id + 1);
            self.emit(Event::BookAdded(BookAdded { book_id, book }));
        }

        fn update_book(ref self: ContractState, book_id: u64, price: u128, quantity: u32) {
            assert(self.owner.read() == get_caller_address(), 'Not owner');
            let mut book = self.books.entry(book_id).read();
            book.price = price;
            book.quantity = quantity;
            self.books.entry(book_id).write(book);
            self.emit(Event::BookUpdated(BookUpdated { book_id, price, quantity }));
        }

        fn remove_book(ref self: ContractState, book_id: u64) {
            assert(self.owner.read() == get_caller_address(), 'Not owner');
            let existing_book = self.books.entry(book_id).read();
            self.books.entry(book_id).write(Book {
                title: existing_book.title,
                description: existing_book.description,
                price: 0,
                author: existing_book.author,
                quantity: 0,
            });
            self.emit(Event::BookRemoved(BookRemoved { book_id }));
        }

        fn get_book(self: @ContractState, book_id: u64) -> Book {
            self.books.entry(book_id).read()
        }

        fn get_book_count(self: @ContractState) -> u64 {
            self.book_count.read()
        }

        fn purchase_book(ref self: ContractState, book_id: u64, quantity: u32) {
            let mut book = self.books.entry(book_id).read();
            assert(book.quantity >= quantity, 'Insufficient stock');

            book.quantity -= quantity;
            self.books.entry(book_id).write(book);

            self.emit(Event::BookSold(BookSold {
                book_id,
                quantity,
                buyer: get_caller_address(),
            }));
        }
    }
}




#[starknet::interface]
trait IPurchase<TContractState> {
    fn purchase_book(ref self: TContractState, bookstore_address: ContractAddress, book_id: u64, quantity: u32);
}

#[starknet::contract]
mod Purchase {
    use core::starknet::ContractAddress;
    use super::IBookstoreDispatcher;
    use super::Book;
    use core::starknet::storage::{ StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        total_purchases: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.total_purchases.write(0);
    }

    #[abi(embed_v0)]
    impl PurchaseImpl of super::IPurchase<ContractState> {
        fn purchase_book(ref self: ContractState, bookstore_address: ContractAddress, book_id: u64, quantity: u32) {
            // Instantiate the dispatcher
            let mut bookstore = IBookstoreDispatcher { contract_address: bookstore_address };

            // Get book details from the bookstore
            let book: Book = bookstore.get_book(book_id);

            assert(book.quantity >= quantity, 'Out of stock');


            // Call `purchase_book` method on the bookstore contract using dispatcher
            bookstore.purchase_book(book_id, quantity);

            self.total_purchases.write(self.total_purchases.read() + 1);
        }
    }
}
